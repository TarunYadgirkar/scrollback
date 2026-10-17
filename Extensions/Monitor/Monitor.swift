import DeviceActivity
import Foundation
import ScrollbackCore
import WidgetKit

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

    /// iOS can suspend the extension as soon as a callback returns, so wait for the write.
    private func record(minutes: Int) {
        guard let store = try? SessionStore(url: SessionStore.defaultURL()) else { return }
        let milestone = Milestone(at: .now, minutes: minutes)
        let written = DispatchSemaphore(value: 0)
        Task {
            try? await store.appendMilestone(milestone)
            written.signal()
        }
        _ = written.wait(timeout: .now() + Self.writeTimeout)
        reloadWidget(at: milestone)
    }

    /// Reloads from here spend the widget's daily budget (about 40–70), and a heavy day reaches 80 steps,
    /// so redraw at most every 15 minutes, plus at each restart so a new day shows 0. Opening the app catches up for free.
    private func reloadWidget(at milestone: Milestone) {
        let defaults = SharedContainer.defaults
        let last = defaults?.object(forKey: Self.widgetReloadKey) as? Date ?? .distantPast
        guard milestone.minutes == 0 || milestone.at.timeIntervalSince(last) >= Self.widgetReloadSpacing else { return }
        defaults?.set(milestone.at, forKey: Self.widgetReloadKey)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedContainer.doomscrollWidgetKind)
    }

    static let writeTimeout: DispatchTimeInterval = .seconds(3)
    static let widgetReloadSpacing: TimeInterval = 15 * 60
    static let widgetReloadKey = "widgetReloadedAt"
}
