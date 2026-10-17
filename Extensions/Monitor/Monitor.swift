import DeviceActivity
import Foundation
import ScrollbackCore
import UserNotifications

/// Wakes each time doomscroll-app use crosses another 5-minute step and notes when it happened.
/// The app turns those timestamps back into a live timeline, and a long unbroken run gets a nudge.
final class Monitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        record(minutes: 0)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        guard let minutes = DoomscrollLadder.minutes(from: event) else { return }
        record(minutes: minutes)
    }

    /// iOS can suspend the extension as soon as a callback returns, so wait for the write and the nudge.
    private func record(minutes: Int) {
        guard let store = try? SessionStore(url: SessionStore.defaultURL()) else { return }
        let milestone = Milestone(at: .now, minutes: minutes)
        let done = DispatchSemaphore(value: 0)
        Task {
            try? await store.appendMilestone(milestone)
            if minutes > 0 { await Self.nudgeIfDue(store: store, now: milestone.at) }
            done.signal()
        }
        _ = done.wait(timeout: .now() + Self.callbackTimeout)
    }

    private static func nudgeIfDue(store: SessionStore, now: Date) async {
        let defaults = SharedContainer.defaults
        // A step while locked is a phantom (Screen Time fires them on the charger): remember it so
        // neither it nor anything before it counts toward a run, and don't nudge.
        guard LockProbe.isUnlocked else {
            defaults?.set(now, forKey: lastLockedKey)
            return
        }
        guard let milestones = try? await store.milestones(after: now.addingTimeInterval(-DoomscrollNudge.lookback)),
              let run = DoomscrollNudge.due(
                  milestones: milestones, now: now,
                  lastNudged: defaults?.object(forKey: lastNudgedKey) as? Date,
                  lastLocked: defaults?.object(forKey: lastLockedKey) as? Date
              )
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(run.minutes) minutes of scrolling"
        content.body = "Nonstop since about \(run.start.formatted(date: .omitted, time: .shortened))."
        content.sound = .default
        content.threadIdentifier = "doomscroll"
        // One identifier per run, so a duplicate callback replaces the nudge instead of stacking a second.
        let id = "doomscroll.\(Int(run.start.timeIntervalSince1970))"
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            defaults?.set(run.end, forKey: lastNudgedKey)
        } catch {
            // Notifications are off; try again on the next step in case they get turned on.
        }
    }

    static let lastNudgedKey = "doomscrollNudge.lastNudgedAt"
    static let lastLockedKey = "doomscrollNudge.lastLockedStep"
    static let callbackTimeout: DispatchTimeInterval = .seconds(5)
}
