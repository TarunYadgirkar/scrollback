import Foundation

/// When to send the "you've been doomscrolling for a while" notification, read from monitor milestones.
/// It only nudges; nothing is blocked.
public enum DoomscrollNudge {
    /// Minutes of unbroken doomscroll-app use before the nudge.
    public static let thresholdMinutes = 20
    /// How far back the monitor should read milestones: past the longest run the ladder can see.
    public static let lookback: TimeInterval = 13 * 3600
    /// A step that arrives much faster than its minutes can't be real use (a phantom or premature callback),
    /// so it's skipped. The slack absorbs a late callback, which makes the step after it look early.
    static let minimumPace = 0.8
    static let paceSlack: TimeInterval = 90
    /// The callback that triggers a nudge must be about now, so a late duplicate can't nudge about an old run.
    static let freshness: TimeInterval = 120
    /// The first ladder step; a restart (midnight, or monitoring restarted) within this much of the
    /// last step, followed by back-to-back steps, doesn't end the run.
    static let stepMinutes = 5

    /// An unbroken run of use ending at the latest milestone.
    public struct Run: Sendable, Equatable {
        /// When the run began; stable while the run keeps going, so it identifies the run.
        public let start: Date
        public let end: Date
        public let minutes: Int
    }

    /// The run to nudge about right now, or nil when there's nothing new to say.
    /// `lastNudged` is the start of the run that was already nudged, so each run nudges once.
    /// `lastLocked` is the latest step that fired while the phone was locked; nothing before it counts.
    public static func due(milestones: [Milestone], now: Date, lastNudged: Date?, lastLocked: Date? = nil) -> Run? {
        guard let run = currentRun(in: milestones, lastLocked: lastLocked),
              run.minutes >= thresholdMinutes,
              now.timeIntervalSince(run.end) <= freshness,
              run.start != lastNudged
        else { return nil }
        return run
    }

    /// Walks back from the latest milestone while steps come back to back, the way `MilestoneTimeline`
    /// joins them into one sitting. The first step of the run counts in full, as the timeline draws it.
    static func currentRun(in milestones: [Milestone], lastLocked: Date? = nil) -> Run? {
        let steps = cleaned(milestones)
        let kept = trusted(steps)
        guard let last = kept.last, last.at == steps.last?.at, !last.isRestart else { return nil }

        var start = last.at
        var minutes = 0
        for (previous, current) in zip(kept, kept.dropFirst()).reversed() {
            let wall = current.at.timeIntervalSince(previous.at)
            if current.isRestart {
                // Counting started over, so the minutes in between weren't counted; join only if the
                // gap is no longer than a step, and credit the wall time.
                guard wall <= TimeInterval(stepMinutes * 60) * MilestoneTimeline.continuityFactor else { break }
                minutes += Int(wall / 60)
            } else {
                let budget = TimeInterval(current.minutes - previous.minutes) * 60
                minutes += current.minutes - previous.minutes
                guard wall <= budget * MilestoneTimeline.continuityFactor else {
                    // Used somewhere in the gap; like the timeline, place those minutes right before the step.
                    start = current.at.addingTimeInterval(-budget)
                    break
                }
            }
            start = previous.at
            if let lastLocked, previous.at <= lastLocked { break }
        }
        guard minutes > 0 else { return nil }
        return Run(start: start, end: last.at, minutes: minutes)
    }

    /// A milestone with minutes counted across restarts, so they only go up.
    struct Step: Equatable {
        let at: Date
        let minutes: Int
        let isRestart: Bool
    }

    /// Oldest first, minutes made cumulative across restarts (0), and duplicate callbacks dropped.
    static func cleaned(_ milestones: [Milestone]) -> [Step] {
        var steps: [Step] = []
        var offset = 0
        var highest = 0
        for milestone in milestones.sorted(by: { $0.at < $1.at }) {
            if milestone.minutes == 0 {
                offset = highest
                steps.append(Step(at: milestone.at, minutes: offset, isRestart: true))
            } else if offset + milestone.minutes > highest {
                highest = offset + milestone.minutes
                steps.append(Step(at: milestone.at, minutes: highest, isRestart: false))
            }
        }
        return steps
    }

    /// Drops steps that came too fast after the last believable one.
    static func trusted(_ steps: [Step]) -> [Step] {
        var kept: [Step] = []
        for step in steps {
            if let previous = kept.last, !step.isRestart {
                let wall = step.at.timeIntervalSince(previous.at)
                let budget = TimeInterval(step.minutes - previous.minutes) * 60
                guard wall >= budget * minimumPace - paceSlack else { continue }
            }
            kept.append(step)
        }
        return kept
    }
}
