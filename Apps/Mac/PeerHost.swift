import Foundation
import Observation
import ScrollbackCore

@MainActor @Observable
final class PeerStatus {
    private static let lastFetchKey = "peer.lastFetch"

    /// When the iPhone last pulled history from this Mac. Kept across launches, so a fresh login
    /// doesn't read as if the phone had never synced.
    private(set) var lastFetch: Date? = UserDefaults.standard.object(forKey: PeerStatus.lastFetchKey) as? Date
    /// A problem worth showing; nil while the listener is healthy.
    private(set) var problem: String?
    private var isStarting = true

    func update(_ state: PeerServer.Status) {
        isStarting = false
        switch state {
        case .synced(let date):
            lastFetch = date
            problem = nil
            UserDefaults.standard.set(date, forKey: Self.lastFetchKey)
        case .waiting:
            problem = nil
        case .paused(let reason):
            problem = "iPhone sync is paused: \(reason)"
        case .requestFailed:
            // One dropped request isn't news; the phone retries on its next refresh.
            break
        case .stopped, .failed:
            problem = state.description
        }
    }

    func failedToStart(_ error: any Error) {
        isStarting = false
        problem = "iPhone sync couldn't start: \(error.localizedDescription)"
    }

    var text: String {
        if let problem { return problem }
        if let lastFetch { return "iPhone last synced \(Self.relative(lastFetch))" }
        return isStarting ? "iPhone sync is starting" : "Ready for your iPhone on this Wi-Fi"
    }

    private static func relative(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "at \(time)" }
        if calendar.isDateInYesterday(date) { return "yesterday at \(time)" }
        return date.formatted(.dateTime.weekday(.wide).hour().minute())
    }
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
                Task { @MainActor in status.update(state) }
            }
            try server.start()
            self.server = server
        } catch {
            status.failedToStart(error)
        }
    }
}
