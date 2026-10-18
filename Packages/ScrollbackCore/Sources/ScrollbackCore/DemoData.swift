import Foundation

/// A made-up week of iPhone and Mac use for demos and screenshots. Nothing here comes from a device:
/// every session is built from the fixed routine below, nudged a little per day so days differ.
public enum DemoData {
    struct Step {
        let bundleID: String
        let minutes: Double
        var reason: OpenReason? = nil
    }

    struct Block {
        let device: DeviceKind
        /// Local clock time the block starts, in hours.
        let at: Double
        let steps: [Step]
        var weekdaysOnly = false
    }

    static let routine: [Block] = [
        Block(device: .iphone, at: 7.2, steps: [
            Step(bundleID: "com.apple.mobiletimer", minutes: 0.6, reason: .notification),
            Step(bundleID: "com.apple.MobileSMS", minutes: 3, reason: .notification),
            Step(bundleID: "com.burbn.instagram", minutes: 7, reason: .homeScreen),
            Step(bundleID: "com.google.Gmail", minutes: 2, reason: .appSwitcher),
        ]),
        Block(device: .iphone, at: 8.4, steps: [
            Step(bundleID: "com.spotify.client", minutes: 1.5, reason: .widget),
            Step(bundleID: "com.reddit.Reddit", minutes: 9, reason: .homeScreen),
            Step(bundleID: "com.atebits.Tweetie2", minutes: 5, reason: .appSwitcher),
            Step(bundleID: "com.apple.Maps", minutes: 2, reason: .spotlight),
        ]),
        Block(device: .mac, at: 9.1, steps: [
            Step(bundleID: "com.tinyspeck.slackmacgap", minutes: 6),
            Step(bundleID: "com.apple.dt.Xcode", minutes: 41),
            Step(bundleID: "com.apple.Terminal", minutes: 7),
            Step(bundleID: "com.apple.Safari", minutes: 9),
            Step(bundleID: "com.apple.dt.Xcode", minutes: 33),
            Step(bundleID: "com.notion.id", minutes: 12),
        ], weekdaysOnly: true),
        Block(device: .iphone, at: 10.6, steps: [
            Step(bundleID: "com.apple.MobileSMS", minutes: 2, reason: .notification),
        ]),
        Block(device: .mac, at: 11.4, steps: [
            Step(bundleID: "com.figma.Desktop", minutes: 24),
            Step(bundleID: "com.linear", minutes: 6),
            Step(bundleID: "com.apple.mail", minutes: 5),
        ], weekdaysOnly: true),
        Block(device: .iphone, at: 12.3, steps: [
            Step(bundleID: "com.burbn.instagram", minutes: 8, reason: .homeScreen),
            Step(bundleID: "com.zhiliaoapp.musically", minutes: 14, reason: .appSwitcher),
            Step(bundleID: "com.google.ios.youtube", minutes: 6, reason: .link),
        ]),
        Block(device: .mac, at: 13.2, steps: [
            Step(bundleID: "com.apple.dt.Xcode", minutes: 52),
            Step(bundleID: "com.anthropic.claudefordesktop", minutes: 8),
            Step(bundleID: "com.apple.Terminal", minutes: 11),
            Step(bundleID: "com.tinyspeck.slackmacgap", minutes: 4),
            Step(bundleID: "com.apple.dt.Xcode", minutes: 46),
            Step(bundleID: "com.apple.Safari", minutes: 14),
        ], weekdaysOnly: true),
        Block(device: .iphone, at: 15.7, steps: [
            Step(bundleID: "com.tinyspeck.chatlyio", minutes: 3, reason: .notification),
            Step(bundleID: "com.atebits.Tweetie2", minutes: 4, reason: .homeScreen),
        ]),
        Block(device: .mac, at: 16.2, steps: [
            Step(bundleID: "com.linear", minutes: 9),
            Step(bundleID: "com.apple.dt.Xcode", minutes: 38),
            Step(bundleID: "com.apple.mail", minutes: 6),
        ], weekdaysOnly: true),
        Block(device: .iphone, at: 18.6, steps: [
            Step(bundleID: "net.whatsapp.WhatsApp", minutes: 5, reason: .notification),
            Step(bundleID: "com.apple.camera", minutes: 1, reason: .other),
            Step(bundleID: "com.apple.mobileslideshow", minutes: 3, reason: .appSwitcher),
        ]),
        Block(device: .mac, at: 20.0, steps: [
            Step(bundleID: "com.apple.Safari", minutes: 26),
            Step(bundleID: "com.spotify.client", minutes: 4),
        ]),
        Block(device: .iphone, at: 21.2, steps: [
            Step(bundleID: "com.zhiliaoapp.musically", minutes: 18, reason: .homeScreen),
            Step(bundleID: "com.burbn.instagram", minutes: 9, reason: .appSwitcher),
            Step(bundleID: "com.reddit.Reddit", minutes: 12, reason: .appSwitcher),
            Step(bundleID: "com.zhiliaoapp.musically", minutes: 7, reason: .appSwitcher),
        ]),
        Block(device: .iphone, at: 23.1, steps: [
            Step(bundleID: "com.apple.mobilesafari", minutes: 5, reason: .link),
            Step(bundleID: "com.apple.mobiletimer", minutes: 0.5, reason: .homeScreen),
        ]),
    ]

    /// `days` of made-up sessions ending at `now`; today stops at `now`.
    public static func sessions(endingAt now: Date, days: Int = 7, calendar: Calendar = .current) -> [Session] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).flatMap { offset -> [Session] in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
            return sessions(on: day, calendar: calendar)
        }
        .compactMap { $0.clipped(to: DateInterval(start: .distantPast, end: now)) }
        .sorted { $0.start < $1.start }
    }

    static func sessions(on day: Date, calendar: Calendar) -> [Session] {
        var random = SplitMix64(seed: UInt64(bitPattern: Int64(day.timeIntervalSince1970)))
        let isWeekend = calendar.isDateInWeekend(day)
        var lastEnd: [DeviceKind: Date] = [:]
        return routine.flatMap { block -> [Session] in
            guard !(block.weekdaysOnly && isWeekend) else { return [] }
            var cursor = day.addingTimeInterval(block.at * 3600 + random.next(in: -15...15) * 60)
            // A long block before can run past the next one's start; keep a break between them.
            if let previous = lastEnd[block.device] {
                cursor = max(cursor, previous.addingTimeInterval(random.next(in: 3...8) * 60))
            }
            let sessions = block.steps.map { step in
                let length = step.minutes * 60 * random.next(in: 0.75...1.25)
                let session = Session(device: block.device, bundleID: step.bundleID, start: cursor, end: cursor.addingTimeInterval(length), reason: step.reason)
                cursor = session.end.addingTimeInterval(random.next(in: 5...50))
                return session
            }
            lastEnd[block.device] = sessions.last?.end
            return sessions
        }
    }
}

/// Small seeded generator, so a given day always gets the same made-up sessions.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
