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
    /// If the next 5 minutes of use landed within this much wall time, treat them as one sitting.
    static let continuityFactor = 1.5

    /// Each milestone means `step` minutes of doomscroll use ended at that moment. When they come
    /// back to back, those minutes were spent continuously right before it; otherwise we only know
    /// they happened somewhere in the gap, so place them at its end (when the step was reached).
    public static func sessions(from milestones: [Milestone], stepMinutes: Int) -> [Session] {
        let step = TimeInterval(stepMinutes * 60)
        let sorted = milestones.sorted { $0.at < $1.at }
        return zip(sorted, sorted.dropFirst()).compactMap { previous, current in
            guard current.minutes > previous.minutes else { return nil }
            let accrued = TimeInterval(current.minutes - previous.minutes) * 60
            let wall = current.at.timeIntervalSince(previous.at)
            let start = wall <= accrued * continuityFactor ? previous.at : current.at.addingTimeInterval(-min(accrued, step))
            return Session(device: .iphone, bundleID: bundleID, start: max(start, previous.at), end: current.at, reason: nil)
        }
    }
}
