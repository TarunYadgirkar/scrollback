@preconcurrency import DeviceActivity
import FamilyControls
import Foundation
import ScrollbackCore

/// Asks Screen Time to wake the monitor extension at every 5-minute step of doomscroll-app use.
@MainActor
enum DoomscrollMonitoring {
    static func start(_ selection: FamilyActivitySelection) async throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring([.doomscroll])
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else { return }

        let wholeDay = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        let steps = stride(from: DoomscrollLadder.stepMinutes, through: DoomscrollLadder.maxMinutes, by: DoomscrollLadder.stepMinutes)
        let events = Dictionary(uniqueKeysWithValues: steps.map { minutes in
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
    }
}
