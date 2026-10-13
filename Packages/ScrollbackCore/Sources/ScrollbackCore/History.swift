import Foundation

/// One device's day boiled down for comparisons: totals plus a running total in 15-minute steps.
public struct DaySummary: Sendable, Equatable {
    public static let slot: TimeInterval = 15 * 60
    public static let slotsPerDay = 96

    public let day: Date
    public let total: TimeInterval
    public let social: TimeInterval
    /// cumulative[i] = screen time from midnight to the end of slot i.
    public let cumulative: [TimeInterval]
    public let cumulativeSocial: [TimeInterval]

    public init(report: ActivityReport, device: DeviceKind) {
        var perSlot = [TimeInterval](repeating: 0, count: Self.slotsPerDay)
        var socialPerSlot = perSlot
        let start = report.window.start
        for session in report.sessions where session.device == device {
            let isSocial = AppCatalog.category(for: session.bundleID) == .social
            var cursor = session.start
            while cursor < session.end {
                let index = Int(cursor.timeIntervalSince(start) / Self.slot)
                guard index >= 0, index < Self.slotsPerDay else { break }
                let slotEnd = start.addingTimeInterval(Double(index + 1) * Self.slot)
                let piece = min(session.end, slotEnd).timeIntervalSince(cursor)
                perSlot[index] += piece
                if isSocial { socialPerSlot[index] += piece }
                cursor = slotEnd
            }
        }
        day = start
        cumulative = Self.runningTotal(perSlot)
        cumulativeSocial = Self.runningTotal(socialPerSlot)
        total = cumulative.last ?? 0
        social = cumulativeSocial.last ?? 0
    }

    public static func slot(of date: Date, dayStart: Date) -> Int {
        min(slotsPerDay - 1, max(0, Int(date.timeIntervalSince(dayStart) / slot)))
    }

    private static func runningTotal(_ values: [TimeInterval]) -> [TimeInterval] {
        values.reduce(into: [TimeInterval]()) { acc, v in acc.append((acc.last ?? 0) + v) }
    }
}

/// "Your usual": the median of recent days, so one wild night doesn't move it much.
public struct Baseline: Sendable, Equatable {
    public static let minimumDays = 3

    public let days: Int
    public let cumulative: [TimeInterval]
    public let cumulativeSocial: [TimeInterval]

    /// Days with no data at all (before history starts, phone off) are left out.
    public init?(_ summaries: [DaySummary]) {
        let usable = summaries.filter { $0.total > 0 }
        guard usable.count >= Self.minimumDays else { return nil }
        days = usable.count
        cumulative = (0..<DaySummary.slotsPerDay).map { i in median(usable.map { $0.cumulative[i] }) }
        cumulativeSocial = (0..<DaySummary.slotsPerDay).map { i in median(usable.map { $0.cumulativeSocial[i] }) }
    }

    public func total(bySlot slot: Int) -> TimeInterval { cumulative[slot] }
    public func social(bySlot slot: Int) -> TimeInterval { cumulativeSocial[slot] }
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

/// A plain-language line about the day, built from numbers only.
public enum Headline {
    static let quietThreshold: TimeInterval = 5 * 60
    static let peakWindow: TimeInterval = 2 * 3600

    public static func text(for report: ActivityReport, device: DeviceKind, baseline: Baseline?, isToday: Bool, now: Date = .now) -> String {
        let summary = DaySummary(report: report, device: device)
        let soFar = isToday ? " so far" : ""
        let socialPart: String
        if summary.social < quietThreshold {
            socialPart = "Barely any social apps\(soFar)."
        } else if let peak = peakSocialWindow(report: report, device: device) {
            socialPart = "\(Format.duration(summary.social)) of social\(soFar), mostly \(hourRange(peak))."
        } else {
            socialPart = "\(Format.duration(summary.social)) of social\(soFar)."
        }
        guard let baseline else { return socialPart }
        let slot = isToday ? DaySummary.slot(of: now, dayStart: report.window.start) : DaySummary.slotsPerDay - 1
        let difference = summary.cumulative[slot] - baseline.total(bySlot: slot)
        guard abs(difference) >= quietThreshold else { return "About your usual. " + socialPart }
        let direction = difference < 0 ? "less" : "more"
        return "\(Format.duration(abs(difference))) \(direction) than usual\(isToday ? " by now" : ""). " + socialPart
    }

    /// The two-hour window with the most social time, on hour boundaries.
    static func peakSocialWindow(report: ActivityReport, device: DeviceKind) -> DateInterval? {
        let social = report.sessions.filter { $0.device == device && AppCatalog.category(for: $0.bundleID) == .social }
        guard !social.isEmpty else { return nil }
        let candidates = (0..<23).map { hour in
            DateInterval(start: report.window.start.addingTimeInterval(Double(hour) * 3600), duration: peakWindow)
        }
        return candidates.max { a, b in socialTime(social, in: a) < socialTime(social, in: b) }
    }

    private static func socialTime(_ sessions: [Session], in window: DateInterval) -> TimeInterval {
        sessions.compactMap { $0.clipped(to: window) }.reduce(0) { $0 + $1.duration }
    }

    static func hourRange(_ window: DateInterval) -> String {
        "\(hourWord(window.start))–\(hourWord(window.end))"
    }

    private static func hourWord(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12)\(hour < 12 ? "am" : "pm")"
    }
}
