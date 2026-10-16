@preconcurrency import DeviceActivity
import SwiftUI

/// Names shared by the app and its Screen Time extensions; both sides must agree on these strings.
extension DeviceActivityReport.Context {
    static var liveToday: Self { Self("Live today") }
    static var hourByHour: Self { Self("Hour by hour") }
}

extension DeviceActivityName {
    static var doomscroll: Self { Self("doomscroll") }
}

enum DoomscrollLadder {
    /// Every 5 minutes of doomscroll-app use fires one milestone, up to 4 hours a day.
    static let stepMinutes = 5
    static let maxMinutes = 240
    static let prefix = "doom."

    static func eventName(minutes: Int) -> DeviceActivityEvent.Name { .init("\(prefix)\(minutes)") }

    static func minutes(from event: DeviceActivityEvent.Name) -> Int? {
        guard event.rawValue.hasPrefix(prefix) else { return nil }
        return Int(event.rawValue.dropFirst(prefix.count))
    }
}

/// Screen Time draws its cards in another process, so the app has to know their heights up front.
enum ScreenTimeCardSize {
    static let liveToday: CGFloat = 372

    static let hourColumns = 4
    static let hourRows = 24 / hourColumns
    static let hourTile: CGFloat = 72
    static let hourSpacing: CGFloat = 6
    static let hourGrid = CGFloat(hourRows) * hourTile + CGFloat(hourRows - 1) * hourSpacing
}
