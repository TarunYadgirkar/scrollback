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
            // Signal only a saved row; a failed write runs out the wait like a slow one.
            guard (try? await store.appendMilestone(milestone)) != nil else { return }
            written.signal()
        }
        // A write that hasn't landed would only redraw the old total and hold off the next real reload.
        guard written.wait(timeout: .now() + Self.writeTimeout) == .success else { return }
        reloadWidget(at: milestone)
    }

    /// Reloads from here spend the widget's daily budget (about 40–70), and a heavy day reaches 80 steps,
    /// so redraw at most every 15 minutes, plus at each restart so a new day shows 0. The widget schedules its own
    /// catch-up for steps skipped here, and opening the app catches up for free.
    private func reloadWidget(at milestone: Milestone) {
        let defaults = SharedContainer.defaults
        let last = defaults?.object(forKey: SharedContainer.widgetReloadedAtKey) as? Date ?? .distantPast
        // A reload time in the future means the clock went back; don't let it block reloads until it catches up.
        let elapsed = milestone.at.timeIntervalSince(last)
        guard milestone.minutes == 0 || elapsed >= SharedContainer.widgetReloadSpacing - Self.reloadSlack || elapsed < 0 else { return }
        // A restart redraws 0 but doesn't start the spacing: the widget has no step to schedule a catch-up from,
        // so the first steps after it must reload on their own.
        if milestone.minutes > 0 { defaults?.set(milestone.at, forKey: SharedContainer.widgetReloadedAtKey) }
        WidgetCenter.shared.reloadTimelines(ofKind: SharedContainer.doomscrollWidgetKind)
    }

    static let writeTimeout: DispatchTimeInterval = .seconds(3)
    /// Steps 15 minutes apart can land a few seconds short of it; don't let that skip every other one.
    static let reloadSlack: TimeInterval = 60
}
