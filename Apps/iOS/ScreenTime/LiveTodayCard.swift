import DeviceActivity
import SwiftUI

/// Hosts the report extension's live card. The data never leaves the extension; we only size it.
struct LiveTodayCard: View {
    static let height: CGFloat = 420

    var body: some View {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        DeviceActivityReport(.liveToday, filter: DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: end)),
            users: .all,
            devices: .init([.iPhone])
        ))
        .frame(height: Self.height)
        // Screen Time draws this in its own process, which would otherwise swallow swipes meant for the page.
        .allowsHitTesting(false)
    }
}

/// Today's hours, newest first, drawn by the report extension. Sized for every hour so far,
/// since the app can't know which hours had use.
struct HourByHourCard: View {
    static let rowHeight: CGFloat = 92
    static let rowSpacing: CGFloat = 8

    var body: some View {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let hoursSoFar = CGFloat(Calendar.current.component(.hour, from: .now) + 1)
        DeviceActivityReport(.hourByHour, filter: DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: end)),
            users: .all,
            devices: .init([.iPhone])
        ))
        .frame(height: hoursSoFar * (Self.rowHeight + Self.rowSpacing))
        .allowsHitTesting(false)
    }
}
