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

nonisolated struct HourByHourScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .hourByHour
    let content: (HourByHour) -> HourByHourView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> HourByHour {
        await HourByHour.build(from: data)
    }
}

struct HourByHourView: View {
    static let appsPerHour = 4

    let report: HourByHour

    nonisolated init(report: HourByHour) {
        self.report = report
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if report.hours.isEmpty {
                Text("No iPhone use yet today.").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
            }
            ForEach(report.hours) { hour in
                row(hour)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ hour: HourByHour.Hour) -> some View {
        let isCurrent = Calendar.current.isDate(hour.start, equalTo: .now, toGranularity: .hour)
        return VStack(alignment: .leading, spacing: Space.xs + Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(isCurrent ? "\(hour.start.hourLabel) – now" : "\(hour.start.hourLabel) – \(hour.start.addingTimeInterval(3600).hourLabel)")
                    .font(TypeScale.mono.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Palette.ink : Palette.inkMuted)
                if isCurrent {
                    Circle().fill(Palette.messaging).frame(width: 6, height: 6)
                }
                Spacer()
                Text(Format.duration(hour.total)).font(TypeScale.readoutSmall).foregroundStyle(Palette.ink)
            }
            HStack(spacing: Space.m) {
                ForEach(hour.apps.prefix(Self.appsPerHour)) { app in
                    HStack(spacing: Space.xs) {
                        AppTokenIcon(token: app.token, category: app.category, size: 18)
                        Text(Format.duration(app.time)).font(TypeScale.mono).foregroundStyle(Palette.ink)
                    }
                }
                if hour.apps.count > Self.appsPerHour {
                    Text("+\(hour.apps.count - Self.appsPerHour)").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
                }
            }
            .lineLimit(1)
            GeometryReader { proxy in
                let used = max(hour.apps.reduce(0) { $0 + $1.time }, 1)
                let usable = proxy.size.width - CGFloat(max(0, hour.apps.count - 1))
                HStack(spacing: 1) {
                    ForEach(hour.apps) { app in
                        Rectangle()
                            .fill(Palette.category(app.category))
                            .frame(width: max(1, usable * app.time / used))
                    }
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())
        }
        .padding(Space.m)
        .frame(height: HourByHourView.rowHeight, alignment: .top)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    static let rowHeight: CGFloat = 92
}
