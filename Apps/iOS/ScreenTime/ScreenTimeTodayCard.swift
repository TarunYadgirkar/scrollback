import DeviceActivity
import SwiftUI

/// Hosts the report extension's Today view. The data never leaves the extension, and touches on it
/// go to the extension too, so it gets its own region of the screen and scrolls inside itself.
struct ScreenTimeTodayCard: View {
    var context: DeviceActivityReport.Context = .today

    var body: some View {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        DeviceActivityReport(context, filter: DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: end)),
            users: .all,
            devices: .init([.iPhone])
        ))
        .frame(maxHeight: .infinity)
    }
}
