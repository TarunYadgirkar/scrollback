import CryptoKit
import Foundation
import Network
import Synchronization

public enum PeerProtocol {
    public static let serviceType = "_scrollback._tcp"
    static let maxRequestBytes = 4 * 1024
    static let maxResponseBytes = 64 * 1024 * 1024
    static let clockSkewTolerance: TimeInterval = 120
    static let queue = DispatchQueue(label: "scrollback.peer")

    static func withTimeout<T: Sendable>(
        _ limit: Duration,
        error timeoutError: some Error,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(for: limit)
                throw timeoutError
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw timeoutError }
            return result
        }
    }
}

/// One request per connection. `auth` is HMAC-SHA256 over
/// `"<since>|<sentAt>"`, each formatted with `%.3f` (POSIX, unix seconds).
public struct PeerRequest: Codable, Sendable, Equatable {
    public let since: Double
    public let sentAt: Double
    public let auth: String

    public static func make(since: Date, key: SymmetricKey, now: Date = .now) -> PeerRequest {
        let since = milliseconds(since.timeIntervalSince1970)
        let sentAt = milliseconds(now.timeIntervalSince1970)
        let code = HMAC<SHA256>.authenticationCode(for: message(since: since, sentAt: sentAt), using: key.derived(for: .auth))
        return PeerRequest(since: since, sentAt: sentAt, auth: Data(code).base64EncodedString())
    }

    public func verify(key: SymmetricKey, now: Date = .now) -> Bool {
        guard abs(now.timeIntervalSince1970 - sentAt) <= PeerProtocol.clockSkewTolerance,
              let code = Data(base64Encoded: auth)
        else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: Self.message(since: since, sentAt: sentAt), using: key.derived(for: .auth))
    }

    static func message(since: Double, sentAt: Double) -> Data {
        Data(String(format: "%.3f|%.3f", since, sentAt).utf8)
    }

    private static func milliseconds(_ seconds: Double) -> Double {
        (seconds * 1000).rounded() / 1000
    }
}

public enum PeerResponse {
    // The request's auth tag is bound in as associated data so a captured
    // response can't be replayed against a later request.
    public static func seal(_ sessions: [Session], for request: PeerRequest, key: SymmetricKey) throws -> Data {
        let json = try JSONEncoder().encode(sessions)
        return try ChaChaPoly.seal(json, using: key.derived(for: .seal), authenticating: Data(request.auth.utf8)).combined
    }

    public static func open(_ data: Data, for request: PeerRequest, key: SymmetricKey) throws -> [Session] {
        let box = try ChaChaPoly.SealedBox(combined: data)
        let json = try ChaChaPoly.open(box, using: key.derived(for: .seal), authenticating: Data(request.auth.utf8))
        // Rebuilt through init so ids always derive from fields, never from the wire.
        return try JSONDecoder().decode([Session].self, from: json).map {
            Session(device: $0.device, bundleID: $0.bundleID, start: $0.start, end: $0.end, reason: $0.reason)
        }
    }
}

public enum PeerFrame {
    static let headerSize = 4

    public static func frame(_ body: Data) -> Data {
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { Data($0) } + body
    }

    public static func length(fromHeader header: Data) -> Int? {
        guard header.count == headerSize else { return nil }
        return Int(header.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }
}

enum KeyPurpose: String {
    case auth = "scrollback.peer.auth"
    case seal = "scrollback.peer.seal"
}

extension SymmetricKey {
    // Separate subkeys keep the HMAC and the cipher from sharing key material.
    func derived(for purpose: KeyPurpose) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: self, info: Data(purpose.rawValue.utf8), outputByteCount: 32)
    }
}

enum PeerTransportError: Error {
    case closed
    case tooLarge
    case unreachable
}

final class ResumeOnce<T: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<T, any Error>?>

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = Mutex(continuation)
    }

    func resume(with result: Result<T, any Error>) {
        continuation.withLock { $0.take() }?.resume(with: result)
    }
}

extension NWConnection {
    func ready() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let once = ResumeOnce(continuation)
            stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(with: .success(()))
                case .failed, .waiting, .cancelled: once.resume(with: .failure(PeerTransportError.unreachable))
                default: break
                }
            }
            start(queue: PeerProtocol.queue)
        }
    }

    func receiveFrame(maxLength: Int) async throws -> Data {
        let header = try await receive(exactly: PeerFrame.headerSize)
        guard let length = PeerFrame.length(fromHeader: header), length <= maxLength else { throw PeerTransportError.tooLarge }
        return try await receive(exactly: length)
    }

    func send(_ data: Data, final: Bool) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let context: ContentContext = final ? .finalMessage : .defaultMessage
                send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                    if let error { return continuation.resume(throwing: error) }
                    continuation.resume()
                })
            }
        } onCancel: {
            cancel()
        }
    }

    private func receive(exactly count: Int) async throws -> Data {
        var buffer = Data()
        while buffer.count < count {
            buffer.append(try await receiveChunk(upTo: count - buffer.count))
        }
        return buffer
    }

    private func receiveChunk(upTo maximum: Int) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
                receive(minimumIncompleteLength: 1, maximumLength: maximum) { data, _, _, error in
                    if let error { return continuation.resume(throwing: error) }
                    guard let data, !data.isEmpty else { return continuation.resume(throwing: PeerTransportError.closed) }
                    continuation.resume(returning: data)
                }
            }
        } onCancel: {
            cancel()
        }
    }
}
