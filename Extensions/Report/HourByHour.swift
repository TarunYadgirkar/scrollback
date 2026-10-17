@preconcurrency import DeviceActivity
import Foundation
import ScrollbackCore
import SwiftUI

/// Each hour of today that had any use, newest first, with the apps used in it.
nonisolated struct HourByHour: Sendable {
    struct Hour: Identifiable, Sendable {
        let start: Date
        let total: TimeInterval
        let apps: [LiveSummary.App]
        var id: Date { start }
    }

    var hours: [Hour] = []

    static func build(from results: DeviceActivityResults<DeviceActivityData>) async -> HourByHour {
        var hours: [Hour] = []
        for await data in results {
            for await segment in data.activitySegments where segment.totalActivityDuration > 0 {
                var apps: [LiveSummary.App] = []
                for await category in segment.categories {
                    for await activity in category.applications where activity.totalActivityDuration > 0 {
                        let app = activity.application
                        apps.append(LiveSummary.App(
                            name: app.localizedDisplayName ?? app.bundleIdentifier.map(AppCatalog.name(for:)) ?? "Unknown",
                            bundleID: app.bundleIdentifier,
                            time: activity.totalActivityDuration,
                            pickups: activity.numberOfPickups,
                            token: app.token
                        ))
                    }
                }
                hours.append(Hour(start: segment.dateInterval.start, total: segment.totalActivityDuration, apps: apps.sorted { $0.time > $1.time }))
            }
        }
        return HourByHour(hours: hours.sorted { $0.start > $1.start })
    }
}

/// The whole day as a 4×6 grid, so the card is the same height at 8am and 11pm.
/// Each hour shows its total and the apps that took it; social-heavy hours read in signal pink.
struct HourByHourView: View {
    static let appsPerHour = 3

    let report: HourByHour

    nonisolated init(report: HourByHour) {
        self.report = report
    }

    var body: some View {
        Grid(horizontalSpacing: ScreenTimeCardSize.hourSpacing, verticalSpacing: ScreenTimeCardSize.hourSpacing) {
            ForEach(0..<ScreenTimeCardSize.hourRows, id: \.self) { row in
                GridRow {
                    ForEach(0..<ScreenTimeCardSize.hourColumns, id: \.self) { column in
                        tile(row * ScreenTimeCardSize.hourColumns + column)
                    }
                }
            }
        }
    }

    private func tile(_ index: Int) -> some View {
        let start = Calendar.current.date(bySettingHour: index, minute: 0, second: 0, of: .now) ?? .now
        let hour = report.hours.first { Calendar.current.component(.hour, from: $0.start) == index }
        let isCurrent = Calendar.current.component(.hour, from: .now) == index
        let isFuture = start > .now
        return VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                Text(start.hourLabel)
                    .font(TypeScale.monoSmall.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Palette.ink : Palette.inkMuted)
                if isCurrent { Circle().fill(Palette.messaging).frame(width: 5, height: 5) }
            }
            if let hour {
                Text(Format.duration(hour.total))
                    .font(TypeScale.title.weight(.bold))
                    .foregroundStyle(isSocialHeavy(hour) ? Palette.signal : Palette.ink)
                HStack(spacing: Space.xxs) {
                    ForEach(hour.apps.prefix(Self.appsPerHour)) { app in
                        AppTokenIcon(token: app.token, category: app.category, size: 16)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(Space.s)
        .frame(maxWidth: .infinity, minHeight: ScreenTimeCardSize.hourTile, maxHeight: ScreenTimeCardSize.hourTile, alignment: .topLeading)
        .background(hour == nil ? Palette.ink.opacity(isFuture ? 0.02 : 0.04) : Palette.raised, in: RoundedRectangle(cornerRadius: Radius.control))
        .opacity(isFuture ? 0.5 : 1)
    }

    private func isSocialHeavy(_ hour: HourByHour.Hour) -> Bool {
        let social = hour.apps.filter { $0.category == .social }.reduce(0) { $0 + $1.time }
        return social > hour.total / 2
    }
}
