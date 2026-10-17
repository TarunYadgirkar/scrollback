import Foundation

/// When to send the "you've been doomscrolling for a while" notification, read from monitor milestones.
/// It only nudges; nothing is blocked.
public enum DoomscrollNudge {
    /// Minutes of unbroken doomscroll-app use before the nudge.
    public static let thresholdMinutes = 20
    /// How far back the monitor should read milestones: past the longest run the ladder can see,
    /// and far enough that the day's restart is there to anchor the first run of the day.
    public static let lookback: TimeInterval = 24 * 3600
    /// A step that arrives much faster than its minutes can't be real use (a phantom or premature callback),
    /// so it's skipped. The slack lets the step after a slightly late one through.
    static let minimumPace = 0.8
    static let paceSlack: TimeInterval = 90
    /// How late a callback can wake the extension and still join the run: a late step stretches the gap
    /// before it. (If the step after it then looks too early, it's skipped and the next one joins instead.)
    static let lateSlack: TimeInterval = 180
    /// The callback that triggers a nudge must be about now, so a late duplicate can't nudge about an old run.
    static let freshness: TimeInterval = 120
    /// The first ladder step; a restart (midnight, or monitoring restarted) within this much of the
    /// last step, followed by back-to-back steps, doesn't end the run.
    static let stepMinutes = 5

    /// An unbroken run of use ending at the latest milestone.
    public struct Run: Sendable, Equatable {
        public let start: Date
        public let end: Date
        public let minutes: Int
    }

    /// The run to nudge about right now, or nil when there's nothing new to say.
    /// `lastNudged` is when the last nudge went out; a run that was already going then has been nudged.
    /// (Not the run's start: that can shift a step later once the step before it leaves the lookback.)
    /// `lastLocked` is the latest step that fired while the phone was locked; nothing before it counts.
    public static func due(milestones: [Milestone], now: Date, lastNudged: Date?, lastLocked: Date? = nil) -> Run? {
        guard let run = currentRun(in: milestones, lastLocked: lastLocked),
              run.minutes >= thresholdMinutes,
              now.timeIntervalSince(run.end) <= freshness
        else { return nil }
        if let lastNudged, run.start <= lastNudged, lastNudged <= run.end { return nil }
        return run
    }

    /// Walks back from the latest milestone while steps come back to back, the way `MilestoneTimeline`
    /// joins them into one sitting. The first step of the run counts in full, as the timeline draws it.
    static func currentRun(in milestones: [Milestone], lastLocked: Date? = nil) -> Run? {
        let kept = steps(from: milestones)
        // The newest callback must be one we believe, or there's nothing new to say.
        guard let last = kept.last, last.at == milestones.map(\.at).max(), !last.isRestart else { return nil }

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
                guard wall <= budget * MilestoneTimeline.continuityFactor + lateSlack else {
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
    /// A restart is also used to anchor a run after Screen Time's count jumped.
    struct Step: Equatable {
        let at: Date
        let minutes: Int
        let isRestart: Bool
    }

    /// Oldest first, with minutes made cumulative across restarts (0) and only the believable steps kept:
    /// duplicate callbacks and steps that came faster than real time are dropped. If a phantom burst
    /// really moved the count, the steps after it are paced from the burst, so the burst becomes an anchor.
    static func steps(from milestones: [Milestone]) -> [Step] {
        var kept: [Step] = []
        var offset = 0
        var skipped: Step?
        for milestone in milestones.sorted(by: { $0.at < $1.at }) {
            if milestone.minutes == 0 {
                offset = kept.last?.minutes ?? 0
                kept.append(Step(at: milestone.at, minutes: offset, isRestart: true))
                skipped = nil
                continue
            }
            let step = Step(at: milestone.at, minutes: offset + milestone.minutes, isRestart: false)
            guard let previous = kept.last else { kept.append(step); continue }
            guard step.minutes > previous.minutes else { continue }
            if believable(step, after: previous) {
                kept.append(step)
                skipped = nil
            } else if let anchor = skipped, step.minutes > anchor.minutes, believable(step, after: anchor) {
                kept.append(Step(at: anchor.at, minutes: anchor.minutes, isRestart: true))
                kept.append(step)
                skipped = nil
            } else {
                skipped = step
            }
        }
        return kept
    }

    private static func believable(_ step: Step, after previous: Step) -> Bool {
        let wall = step.at.timeIntervalSince(previous.at)
        let budget = TimeInterval(step.minutes - previous.minutes) * 60
        return wall >= budget * minimumPace - paceSlack
    }
}
