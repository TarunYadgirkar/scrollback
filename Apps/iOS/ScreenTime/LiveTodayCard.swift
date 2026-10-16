import DeviceActivity
import SwiftUI

/// Hosts the report extension's live card. The data never leaves the extension; we only size it.
struct LiveTodayCard: View {
    var body: some View {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        DeviceActivityReport(.liveToday, filter: DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: end)),
            users: .all,
            devices: .init([.iPhone])
        ))
        .frame(height: ScreenTimeCardSize.liveToday)
        // Screen Time draws this in its own process, which would otherwise swallow swipes meant for the page.
        .allowsHitTesting(false)
    }
}

/// All 24 hours of today in a fixed grid, drawn by the report extension.
struct HourByHourCard: View {
    var body: some View {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        DeviceActivityReport(.hourByHour, filter: DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: end)),
            users: .all,
            devices: .init([.iPhone])
        ))
        .frame(height: ScreenTimeCardSize.hourGrid)
        .allowsHitTesting(false)
    }
}
