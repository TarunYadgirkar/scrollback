import CryptoKit
import Foundation
import Network

public enum PeerSyncError: Error, Equatable, LocalizedError {
    case notFound
    case rejected
    case timedOut
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .notFound: "Couldn't find your Mac on this Wi-Fi. Open Scrollback on the Mac."
        case .rejected: "Your Mac refused to sync. Reinstall this app from the same Mac so their sync keys match."
        case .timedOut: "Your Mac stopped responding. Check that both are on the same Wi-Fi, then try again."
        case .badResponse: "Your Mac sent data this app couldn't read. Update Scrollback on both devices."
        }
    }
}

public struct PeerClient: Sendable {
    static let discoveryTimeout: Duration = .seconds(5)
    static let overallTimeout: Duration = .seconds(15)
    // Sessions still open on the Mac keep growing; refetching recent days picks up their new end times.
    static let refetchWindow: TimeInterval = 2 * 86_400

    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    public func sync(into store: SessionStore) async throws -> Int {
        try await PeerProtocol.withTimeout(Self.overallTimeout, error: PeerSyncError.timedOut) {
            let endpoint = try await Self.discoverMac()
            return try await pull(from: endpoint, into: store)
        }
    }

    func sync(into store: SessionStore, endpoint: NWEndpoint) async throws -> Int {
        try await PeerProtocol.withTimeout(Self.overallTimeout, error: PeerSyncError.timedOut) {
            try await pull(from: endpoint, into: store)
        }
    }

    private func pull(from endpoint: NWEndpoint, into store: SessionStore) async throws -> Int {
        let request = PeerRequest.make(since: try await Self.since(for: store), key: key)
        let sealed = try await exchange(request, with: endpoint)
        guard let sessions = try? PeerResponse.open(sealed, for: request, key: key) else { throw PeerSyncError.badResponse }
        return try await store.upsert(sessions, markSynced: true)
    }

    private static func since(for store: SessionStore) async throws -> Date {
        guard let latest = try await store.latestEnd() else { return Date(timeIntervalSince1970: 0) }
        return latest.addingTimeInterval(-refetchWindow)
    }

    private func exchange(_ request: PeerRequest, with endpoint: NWEndpoint) async throws -> Data {
        let connection = NWConnection(to: endpoint, using: .tcp)
        defer { connection.cancel() }
        do {
            try await withTaskCancellationHandler {
                try await connection.ready()
            } onCancel: {
                connection.cancel()
            }
        } catch {
            throw PeerSyncError.notFound
        }
        try await connection.send(PeerFrame.frame(try JSONEncoder().encode(request)), final: false)
        do {
            return try await connection.receiveFrame(maxLength: PeerProtocol.maxResponseBytes)
        } catch PeerTransportError.closed {
            throw PeerSyncError.rejected
        } catch PeerTransportError.tooLarge {
            throw PeerSyncError.badResponse
        }
    }

    private static func discoverMac() async throws -> NWEndpoint {
        try await PeerProtocol.withTimeout(discoveryTimeout, error: PeerSyncError.notFound) {
            let browser = NWBrowser(for: .bonjour(type: PeerProtocol.serviceType, domain: nil), using: .tcp)
            defer { browser.cancel() }
            return try await withTaskCancellationHandler {
                try await firstResult(of: browser)
            } onCancel: {
                browser.cancel()
            }
        }
    }

    private static func firstResult(of browser: NWBrowser) async throws -> NWEndpoint {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            browser.browseResultsChangedHandler = { results, _ in
                guard let first = results.first else { return }
                once.resume(with: .success(first.endpoint))
            }
            browser.stateUpdateHandler = { state in
                switch state {
                case .failed, .cancelled: once.resume(with: .failure(PeerSyncError.notFound))
                default: break
                }
            }
            browser.start(queue: PeerProtocol.queue)
        }
    }
}
