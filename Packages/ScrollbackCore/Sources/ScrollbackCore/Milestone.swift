import Foundation

/// "Doomscroll apps reached N minutes today" at a moment, from the Screen Time monitor extension.
/// `minutes == 0` marks where counting (re)started.
public struct Milestone: Sendable, Equatable {
    public let at: Date
    public let minutes: Int

    public init(at: Date, minutes: Int) {
        self.at = at
        self.minutes = minutes
    }
}

public enum MilestoneTimeline {
    public static let bundleID = "scrollback.doomscroll"
    /// If a step's minutes of use landed within this multiple of wall time, treat them as one sitting.
    static let continuityFactor = 1.5

    /// Each milestone means the minutes since the previous one ended at that moment. When they come
    /// back to back, those minutes were spent continuously right before it; otherwise we only know
    /// they happened somewhere in the gap, so place them at its end (when the step was reached).
    public static func sessions(from milestones: [Milestone]) -> [Session] {
        let sorted = milestones.sorted { $0.at < $1.at }
        return zip(sorted, sorted.dropFirst()).compactMap { previous, current in
            guard current.minutes > previous.minutes else { return nil }
            let accrued = TimeInterval(current.minutes - previous.minutes) * 60
            let wall = current.at.timeIntervalSince(previous.at)
            let start = wall <= accrued * continuityFactor ? previous.at : current.at.addingTimeInterval(-accrued)
            return Session(device: .iphone, bundleID: bundleID, start: max(start, previous.at), end: current.at, reason: nil)
        }
    }
}

/// Today's doomscroll total as the monitor last saw it, for the widgets.
public struct DoomscrollToday: Sendable, Equatable {
    public let minutes: Int
    /// When the latest step today was reached, or nil before the first one.
    public let asOf: Date?

    public init(minutes: Int, asOf: Date?) {
        self.minutes = minutes
        self.asOf = asOf
    }

    /// Adds up the steps reached on `now`'s day. Screen Time's counters start over at midnight and at each
    /// restart (a 0 milestone), so each run counts up from 0 and a mid-day restart keeps what came before it.
    /// Counting from the run's highest step, not the previous row, keeps a late or repeated callback from
    /// adding anything twice. Uses the steps themselves, not session lengths, which can run longer than their minutes.
    public static func from(_ milestones: [Milestone], now: Date = .now, calendar: Calendar = .current) -> DoomscrollToday {
        let dayStart = calendar.startOfDay(for: now)
        var runStart = dayStart
        var runHigh = 0
        var minutes = 0
        var asOf: Date?
        for milestone in milestones.sorted(by: { $0.at < $1.at }) where milestone.at >= dayStart && milestone.at <= now {
            if milestone.minutes == 0 {
                runStart = milestone.at
                runHigh = 0
                continue
            }
            // More minutes than the run has lasted is a callback left over from before it (yesterday's, say).
            guard milestone.minutes > runHigh, TimeInterval(milestone.minutes) * 60 <= milestone.at.timeIntervalSince(runStart) + 60 else { continue }
            minutes += milestone.minutes - runHigh
            runHigh = milestone.minutes
            asOf = milestone.at
        }
        return DoomscrollToday(minutes: minutes, asOf: asOf)
    }
}
