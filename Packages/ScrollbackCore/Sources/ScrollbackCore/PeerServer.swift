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
        case failed(String)

        public var description: String {
            switch self {
            case .stopped: "iPhone sync is off"
            case .waiting: "Waiting for iPhone"
            case .synced(let date): "Synced iPhone at \(date.formatted(date: .omitted, time: .shortened))"
            case .failed(let message): "iPhone sync stopped: \(message)"
            }
        }
    }

    static let requestTimeout: Duration = .seconds(10)
    static let connectionLifetime: TimeInterval = 60

    private let store: SessionStore
    private let key: SymmetricKey
    private let onStatusChange: @Sendable (Status) -> Void
    private let listener = Mutex<NWListener?>(nil)

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
        case .waiting(let error): onStatusChange(.failed(error.localizedDescription))
        case .failed(let error): stop(reporting: .failed(error.localizedDescription))
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: PeerProtocol.queue)
        PeerProtocol.queue.asyncAfter(deadline: .now() + Self.connectionLifetime) { connection.cancel() }
        Task {
            await serve(connection)
            connection.cancel()
        }
    }

    private func serve(_ connection: NWConnection) async {
        guard let request = await receiveRequest(on: connection) else { return }
        do {
            let sessions = try await store.sessions(endingAfter: Date(timeIntervalSince1970: request.since))
            let sealed = try PeerResponse.seal(sessions, for: request, key: key)
            guard sealed.count <= PeerProtocol.maxResponseBytes else {
                return onStatusChange(.failed("History is too large to send in one sync"))
            }
            try await connection.send(PeerFrame.frame(sealed), final: true)
            onStatusChange(.synced(at: .now))
        } catch {
            onStatusChange(.failed(error.localizedDescription))
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
              request.verify(key: key)
        else { return nil }
        return request
    }
}
#endif
