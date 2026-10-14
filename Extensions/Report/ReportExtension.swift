@preconcurrency import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct ScrollbackReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        LiveTodayScene { LiveTodayView(summary: $0) }
    }
}

nonisolated struct LiveTodayScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .liveToday
    let content: (LiveSummary) -> LiveTodayView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> LiveSummary {
        await LiveSummary.build(from: data)
    }
}
