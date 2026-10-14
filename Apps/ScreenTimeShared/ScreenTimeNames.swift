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
