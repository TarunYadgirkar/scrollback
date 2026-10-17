@preconcurrency import DeviceActivity
import FamilyControls
import Foundation
import ScrollbackCore
import WidgetKit

/// Asks Screen Time to wake the monitor extension at every step of doomscroll-app use.
@MainActor
enum DoomscrollMonitoring {
    static let monitoredKey = SharedContainer.monitoredSelectionKey

    /// Restarting resets Screen Time's counters and drops the minutes toward the next step,
    /// so only restart when the picked apps changed or monitoring isn't running.
    static func startIfNeeded(_ selection: FamilyActivitySelection) async throws {
        let isRunning = DeviceActivityCenter().activities.contains(.doomscroll)
        guard !isRunning || monitoredSelection() != selection else { return }
        try await start(selection)
    }

    private static func monitoredSelection() -> FamilyActivitySelection? {
        guard let data = SharedContainer.defaults?.data(forKey: monitoredKey) else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    private static func start(_ selection: FamilyActivitySelection) async throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring([.doomscroll])
        SharedContainer.defaults?.removeObject(forKey: monitoredKey)
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else { return }

        let wholeDay = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        let events = Dictionary(uniqueKeysWithValues: DoomscrollLadder.steps.map { minutes in
            (DoomscrollLadder.eventName(minutes: minutes), DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(hour: minutes / 60, minute: minutes % 60)
            ))
        })
        // Thresholds count from now, so mark the restart: milestone minutes are relative to it.
        try await SessionStore(url: SessionStore.defaultURL()).appendMilestone(Milestone(at: .now, minutes: 0))
        try center.startMonitoring(.doomscroll, during: wholeDay, events: events)
        SharedContainer.defaults?.set(try JSONEncoder().encode(selection), forKey: monitoredKey)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedContainer.doomscrollWidgetKind)
    }
}
