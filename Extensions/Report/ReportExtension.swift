@preconcurrency import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct ScrollbackReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TodayScene { TodayView(report: $0) }
        AppsScene { LiveAppsView(summary: $0) }
    }
}

nonisolated struct TodayReport: Sendable {
    let summary: LiveSummary
    let hours: HourByHour
}

nonisolated struct TodayScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .today
    let content: (TodayReport) -> TodayView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayReport {
        TodayReport(summary: await LiveSummary.build(from: data), hours: await HourByHour.build(from: data))
    }
}

/// Every app used today with its total, for the app's "Apps" view.
nonisolated struct AppsScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .apps
    let content: (LiveSummary) -> LiveAppsView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> LiveSummary {
        await LiveSummary.build(from: data)
    }
}

/// The live summary and the hour grid in one scrolling view. iOS sends touches on a Screen Time
/// report to this extension, not the app, so the app's page can't scroll from here; this view scrolls itself.
struct TodayView: View {
    let report: TodayReport

    nonisolated init(report: TodayReport) {
        self.report = report
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                LiveTodayView(summary: report.summary)
                Text("By hour").font(TypeScale.title).foregroundStyle(Palette.ink)
                HourByHourView(report: report.hours)
            }
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
    }
}
