import DeviceActivity
import Foundation
import ScrollbackCore

/// Wakes each time doomscroll-app use crosses another 5-minute step and notes when it happened.
/// The app turns those timestamps back into a live timeline.
final class Monitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        record(minutes: 0)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        guard let minutes = DoomscrollLadder.minutes(from: event) else { return }
        record(minutes: minutes)
    }

    private func record(minutes: Int) {
        guard let store = try? SessionStore(url: SessionStore.defaultURL()) else { return }
        let milestone = Milestone(at: .now, minutes: minutes)
        Task { try? await store.appendMilestone(milestone) }
    }
}
