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

    /// Each milestone means the minutes since the previous one ended at that moment. We only know
    /// they happened somewhere in the gap, so place them at its end (when the step was reached).
    /// When steps come back to back, pull the start in so the gap to the previous step stays within
    /// `BingeDetector.maxGap` and the sitting still chains; that stretches a session past its measured
    /// minutes only when the gap would otherwise exceed it.
    public static func sessions(from milestones: [Milestone]) -> [Session] {
        let sorted = milestones.sorted { $0.at < $1.at }
        return zip(sorted, sorted.dropFirst()).compactMap { previous, current in
            guard current.minutes > previous.minutes else { return nil }
            let accrued = TimeInterval(current.minutes - previous.minutes) * 60
            let wall = current.at.timeIntervalSince(previous.at)
            var start = current.at.addingTimeInterval(-accrued)
            if wall <= accrued * continuityFactor {
                start = min(start, previous.at.addingTimeInterval(BingeDetector.maxGap))
            }
            return Session(device: .iphone, bundleID: bundleID, start: max(start, previous.at), end: current.at, reason: nil)
        }
    }
}
