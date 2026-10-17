import Foundation

/// When to send the "you've been doomscrolling for a while" notification, read from monitor milestones.
/// It only nudges; nothing is blocked.
public enum DoomscrollNudge {
    /// Minutes of unbroken doomscroll-app use before the nudge.
    public static let thresholdMinutes = 20
    /// A step that arrived faster than this share of its minutes can't be real use (premature or phantom callback).
    static let minimumPace = 0.8
    /// The callback that triggers a nudge must be about now, so a late duplicate can't nudge about an old run.
    static let freshness: TimeInterval = 120

    /// An unbroken run of use ending at the latest milestone.
    public struct Run: Sendable, Equatable {
        /// When the run began; stable while the run keeps going, so it identifies the run.
        public let start: Date
        public let end: Date
        public let minutes: Int
    }

    /// The run to nudge about right now, or nil when there's nothing new to say.
    /// `lastNudged` is the start of the run that was already nudged, so each run nudges once.
    public static func due(milestones: [Milestone], now: Date, lastNudged: Date?) -> Run? {
        guard let run = currentRun(in: milestones),
              run.minutes >= thresholdMinutes,
              now.timeIntervalSince(run.end) <= freshness,
              run.start != lastNudged
        else { return nil }
        return run
    }

    /// Walks back from the latest milestone while steps come back to back, the way `MilestoneTimeline`
    /// joins them into one sitting. The first step of the run counts in full, as the timeline draws it.
    static func currentRun(in milestones: [Milestone]) -> Run? {
        let steps = cleaned(milestones)
        guard let last = steps.last, last.minutes > 0 else { return nil }

        var start = last.at
        var minutes = 0
        for (previous, current) in zip(steps, steps.dropFirst()).reversed() {
            guard current.minutes > previous.minutes else { break }
            let accrued = current.minutes - previous.minutes
            let wall = current.at.timeIntervalSince(previous.at)
            let budget = TimeInterval(accrued) * 60
            guard wall >= budget * minimumPace else { break }
            minutes += accrued
            guard wall <= budget * MilestoneTimeline.continuityFactor else {
                // Used somewhere in the gap; like the timeline, place those minutes right before the step.
                start = current.at.addingTimeInterval(-budget)
                break
            }
            start = previous.at
        }
        guard minutes > 0 else { return nil }
        return Run(start: start, end: last.at, minutes: minutes)
    }

    /// Oldest first, without duplicate callbacks: after each restart (0), keep only steps that go up.
    static func cleaned(_ milestones: [Milestone]) -> [Milestone] {
        var kept: [Milestone] = []
        var highest = 0
        for milestone in milestones.sorted(by: { $0.at < $1.at }) {
            if milestone.minutes == 0 {
                highest = 0
            } else if milestone.minutes <= highest {
                continue
            } else {
                highest = milestone.minutes
            }
            kept.append(milestone)
        }
        return kept
    }
}
