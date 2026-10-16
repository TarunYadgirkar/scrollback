@preconcurrency import DeviceActivity
import Foundation
@preconcurrency import ManagedSettings
import ScrollbackCore
import SwiftUI

/// Today's usage as Apple's Screen Time reports it, boiled down for one card.
nonisolated struct LiveSummary: Sendable {
    struct App: Identifiable, Sendable {
        let name: String
        let bundleID: String?
        let time: TimeInterval
        let pickups: Int
        var token: ApplicationToken?
        var id: String { bundleID ?? name }
        var category: AppCategory { bundleID.map(AppCatalog.category(for:)) ?? .other }
    }

    var total: TimeInterval = 0
    var social: TimeInterval = 0
    var pickups = 0
    var apps: [App] = []
    var longest: DateInterval?
    var updated: Date?

    static func build(from results: DeviceActivityResults<DeviceActivityData>) async -> LiveSummary {
        var summary = LiveSummary()
        var appTotals: [String: App] = [:]
        for await data in results {
            summary.updated = max(summary.updated ?? .distantPast, data.lastUpdatedDate)
            for await segment in data.activitySegments {
                var hourSocial: TimeInterval = 0
                summary.pickups += segment.totalPickupsWithoutApplicationActivity
                if let longest = segment.longestActivity, longest.duration > (summary.longest?.duration ?? 0) {
                    summary.longest = longest
                }
                for await category in segment.categories {
                    for await activity in category.applications {
                        let app = activity.application
                        let key = app.bundleIdentifier ?? app.localizedDisplayName ?? "Unknown"
                        let previous = appTotals[key]
                        let merged = App(
                            name: app.localizedDisplayName ?? app.bundleIdentifier.map(AppCatalog.name(for:)) ?? "Unknown",
                            bundleID: app.bundleIdentifier,
                            time: (previous?.time ?? 0) + activity.totalActivityDuration,
                            pickups: (previous?.pickups ?? 0) + activity.numberOfPickups,
                            token: app.token
                        )
                        appTotals[key] = merged
                        summary.pickups += activity.numberOfPickups
                        if merged.category == .social { hourSocial += activity.totalActivityDuration }
                    }
                }
                summary.total += segment.totalActivityDuration
                summary.social += hourSocial
            }
        }
        summary.apps = appTotals.values.sorted { $0.time > $1.time }
        return summary
    }
}
