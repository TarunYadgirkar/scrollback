import DeviceActivity
import Foundation
import ScrollbackCore
import SwiftUI

/// Temporary: checks what the iOS 26.4 `activityData(filteredBy:using:)` API hands the host app
/// (real bundle IDs or only tokens, how fresh, which devices). Writes probe.txt to the App Group.
enum ActivityProbe {
    static let timeout: Duration = .seconds(20)
    static var outputURL: URL? { SharedContainer.url?.appending(path: "probe.txt") }

    static func run() async {
        guard #available(iOS 26.4, *) else { return write(["iOS older than 26.4, API unavailable"]) }
        let lines = await withTaskGroup(of: [String]?.self) { group in
            group.addTask { await collect() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? ["timed out after \(timeout)"]
        }
        write(lines)
    }

    @available(iOS 26.4, *)
    private static func collect() async -> [String] {
        let start = Calendar.current.startOfDay(for: .now)
        let filter = DeviceActivityFilter(segment: .hourly(during: DateInterval(start: start, end: .now)), users: .all, devices: .all)
        var out = ["probe at \(Date.now)"]
        do {
            for try await data in DeviceActivityData.activityData(filteredBy: filter, using: .live) {
                out.append("DATA device=\(data.device.model) name=\(data.device.name ?? "-") updated=\(data.lastUpdatedDate)")
                for await segment in data.activitySegments {
                    out.append(" SEG \(segment.dateInterval.start) total=\(Int(segment.totalActivityDuration))s longest=\(segment.longestActivity.map { "\($0.start)-\($0.end)" } ?? "-") firstPickup=\(segment.firstPickup.map { "\($0)" } ?? "-")")
                    for await category in segment.categories {
                        for await app in category.applications {
                            out.append("   \(app.application.bundleIdentifier ?? "nil") | \(app.application.localizedDisplayName ?? "nil") | \(Int(app.totalActivityDuration))s | pickups \(app.numberOfPickups) | notifs \(app.numberOfNotifications)")
                        }
                    }
                }
                if out.count > 400 { break }
            }
        } catch {
            out.append("ERROR \(error)")
        }
        return out
    }

    private static func write(_ lines: [String]) {
        guard let url = outputURL else { return }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
