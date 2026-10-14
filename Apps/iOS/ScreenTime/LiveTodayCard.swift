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
    }
}
