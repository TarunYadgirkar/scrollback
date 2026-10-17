#if os(macOS)
import CryptoKit
import Foundation
import Network
import Synchronization

public final class PeerServer: Sendable {
    public enum Status: Sendable, Equatable, CustomStringConvertible {
        case stopped
        case waiting
        case synced(at: Date)
        /// The listener is still up but can't take connections yet, e.g. no network.
        case paused(String)
        /// One iPhone request didn't complete; the listener keeps serving.
        case requestFailed(String)
        case failed(String)

        public var description: String {
            switch self {
            case .stopped: "iPhone sync is off"
            case .waiting: "Waiting for iPhone"
            case .synced(let date): "Synced iPhone at \(date.formatted(date: .omitted, time: .shortened))"
            case .paused(let message): "iPhone sync is paused: \(message)"
            case .requestFailed(let message): "Last iPhone sync didn't finish: \(message)"
            case .failed(let message): "iPhone sync stopped: \(message)"
            }
        }
    }

    static let requestTimeout: Duration = .seconds(3)
    static let connectionLifetime: TimeInterval = 60
    static let maxConcurrentConnections = 4

    private let store: SessionStore
    private let key: SymmetricKey
    private let onStatusChange: @Sendable (Status) -> Void
    private let listener = Mutex<NWListener?>(nil)
    private let inFlight = Mutex(0)
    /// Auth tags seen inside the clock-skew window; a repeat is a replayed request.
    private let seenAuth = Mutex<[String: Date]>([:])

    public init(store: SessionStore, key: SymmetricKey, onStatusChange: @escaping @Sendable (Status) -> Void = { _ in }) {
        self.store = store
        self.key = key
        self.onStatusChange = onStatusChange
    }

    var port: NWEndpoint.Port? {
        listener.withLock { $0?.port }
    }

    public func start() throws {
        let next = try NWListener(using: .tcp)
        next.service = NWListener.Service(type: PeerProtocol.serviceType)
        next.stateUpdateHandler = { [weak self] state in self?.listenerChanged(to: state) }
        next.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        let previous = listener.withLock { current in
            let old = current
            current = next
            return old
        }
        previous?.cancel()
        next.start(queue: PeerProtocol.queue)
    }

    public func stop() {
        stop(reporting: .stopped)
    }

    private func stop(reporting status: Status) {
        listener.withLock { $0.take() }?.cancel()
        onStatusChange(status)
    }

    private func listenerChanged(to state: NWListener.State) {
        switch state {
        case .ready: onStatusChange(.waiting)
        case .waiting(let error): onStatusChange(.paused(error.localizedDescription))
        case .failed(let error): stop(reporting: .failed(error.localizedDescription))
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        let admitted = inFlight.withLock { count in
            guard count < Self.maxConcurrentConnections else { return false }
            count += 1
            return true
        }
        guard admitted else { return connection.cancel() }
        connection.start(queue: PeerProtocol.queue)
        PeerProtocol.queue.asyncAfter(deadline: .now() + Self.connectionLifetime) { connection.cancel() }
        Task {
            await serve(connection)
            connection.cancel()
            inFlight.withLock { $0 -= 1 }
        }
    }

    private func isFirstUse(of request: PeerRequest, now: Date = .now) -> Bool {
        seenAuth.withLock { seen in
            seen = seen.filter { now.timeIntervalSince($0.value) <= PeerProtocol.clockSkewTolerance * 2 }
            guard seen[request.auth] == nil else { return false }
            seen[request.auth] = now
            return true
        }
    }

    private func serve(_ connection: NWConnection) async {
        guard let request = await receiveRequest(on: connection) else { return }
        do {
            let sessions = try await store.sessions(endingAfter: Date(timeIntervalSince1970: request.since))
            let sealed = try PeerResponse.seal(sessions, for: request, key: key)
            guard sealed.count <= PeerProtocol.maxResponseBytes else {
                return onStatusChange(.requestFailed("History is too large to send in one sync"))
            }
            try await connection.send(PeerFrame.frame(sealed), final: true)
            onStatusChange(.synced(at: .now))
        } catch {
            onStatusChange(.requestFailed(error.localizedDescription))
        }
    }

    // Malformed, stale, or unauthenticated requests get no reply at all, so a
    // stranger on the network learns nothing beyond the open port.
    private func receiveRequest(on connection: NWConnection) async -> PeerRequest? {
        let body = try? await PeerProtocol.withTimeout(Self.requestTimeout, error: PeerTransportError.closed) {
            try await connection.receiveFrame(maxLength: PeerProtocol.maxRequestBytes)
        }
        guard let body,
              let request = try? JSONDecoder().decode(PeerRequest.self, from: body),
              request.verify(key: key),
              isFirstUse(of: request)
        else { return nil }
        return request
    }
}
#endif
