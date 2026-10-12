import Foundation
import Observation
import ScrollbackCore

@MainActor @Observable
final class PeerStatus {
    var text = "iPhone sync is starting"
}

/// Serves this Mac's sessions to the iPhone app over the local network.
@MainActor
final class PeerHost {
    private let store: SessionStore
    private let status: PeerStatus
    private var server: PeerServer?

    init(store: SessionStore, status: PeerStatus) {
        self.store = store
        self.status = status
    }

    func start() {
        do {
            let key = try PeerKey.loadOrCreateOnMac()
            let server = PeerServer(store: store, key: key) { [status] state in
                Task { @MainActor in status.text = state.description }
            }
            try server.start()
            self.server = server
        } catch {
            status.text = "iPhone sync is off: \(error)"
        }
    }
}
