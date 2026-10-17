import Foundation
import Testing
@testable import ScrollbackCore

@Suite struct SessionizerTests {
    @Test func pairsStartAndEnd() {
        let sessions = Sessionizer.sessions(from: [
            start("com.burbn.instagram", .at(19, 0), .notification),
            end("com.burbn.instagram", .at(19, 10)),
        ], device: .iphone)

        #expect(sessions.count == 1)
        #expect(sessions[0].duration == 600)
        #expect(sessions[0].reason == .notification)
    }

    @Test func newStartClosesUnfinishedSession() {
        let sessions = Sessionizer.sessions(from: [
            start("com.burbn.instagram", .at(19, 0)),
            start("com.atebits.Tweetie2", .at(19, 4)),
            end("com.atebits.Tweetie2", .at(19, 6)),
        ], device: .iphone)

        #expect(sessions.map(\.bundleID) == ["com.burbn.instagram", "com.atebits.Tweetie2"])
        #expect(sessions[0].end == .at(19, 4))
    }

    @Test func lockScreenEndsSessionButIsNotUsage() {
        let sessions = Sessionizer.sessions(from: [
            start("com.burbn.instagram", .at(23, 50)),
            start("com.apple.SleepLockScreen", .at(23, 55)),
            end("com.apple.SleepLockScreen", .at(7, 30, day: 12)),
        ], device: .iphone)

        #expect(sessions.map(\.bundleID) == ["com.burbn.instagram"])
        #expect(sessions[0].end == .at(23, 55))
    }

    @Test func dropsTrailingOpenSessionAndSubSecondBlips() {
        let sessions = Sessionizer.sessions(from: [
            start("com.apple.mobilesafari", .at(10, 0)),
            end("com.apple.mobilesafari", .at(10, 0)),
            start("com.burbn.instagram", .at(10, 1)),
        ], device: .iphone)

        #expect(sessions.isEmpty)
    }

    @Test func idsAreStableAcrossReingest() {
        let events = [start("com.burbn.instagram", .at(19, 0)), end("com.burbn.instagram", .at(19, 1))]
        #expect(Sessionizer.sessions(from: events, device: .iphone) == Sessionizer.sessions(from: events.reversed(), device: .iphone))
    }
}

@Suite struct BingeTests {
    func session(_ id: String, _ from: Date, _ to: Date, device: DeviceKind = .iphone) -> Session {
        Session(device: device, bundleID: id, start: from, end: to, reason: nil)
    }

    @Test func chainsSocialAppsWithinTwoMinutes() {
        let binges = BingeDetector.binges(in: [
            session("com.burbn.instagram", .at(23, 0), .at(23, 15)),
            session("com.apple.MobileSMS", .at(23, 15, 10), .at(23, 15, 50)),
            session("com.atebits.Tweetie2", .at(23, 16, 30), .at(23, 30)),
            session("com.burbn.instagram", .at(23, 31), .at(23, 47)),
            session("com.burbn.instagram", .at(23, 55), .at(23, 58)),
        ])

        #expect(binges.count == 1)
        #expect(binges[0].span == 47 * 60)
        #expect(binges[0].hops == ["com.burbn.instagram", "com.atebits.Tweetie2", "com.burbn.instagram"])
        let expectedActive: TimeInterval = 900 + 810 + 960
        #expect(binges[0].activeTime == expectedActive)
    }

    @Test func ignoresShortRunsAndNonSocialApps() {
        let binges = BingeDetector.binges(in: [
            session("com.burbn.instagram", .at(9, 0), .at(9, 3)),
            session("com.anthropic.claude", .at(10, 0), .at(11, 0)),
        ])
        #expect(binges.isEmpty)
    }

    @Test func neverChainsAcrossDevices() {
        let binges = BingeDetector.binges(in: [
            session("com.burbn.instagram", .at(20, 0), .at(20, 4)),
            session("com.atebits.Tweetie2", .at(20, 4, 30), .at(20, 8), device: .mac),
        ])
        #expect(binges.isEmpty)
    }
}

@Suite struct StoreTests {
    @Test func upsertIsIdempotentAndTracksSync() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "scrollback-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SessionStore(url: url)
        let s = Session(device: .iphone, bundleID: "com.burbn.instagram", start: .at(19, 0), end: .at(19, 10), reason: .homeScreen)

        #expect(try await store.upsert([s]) == 1)
        #expect(try await store.upsert([s]) == 0)
        #expect(try await store.unsynced().map(\.id) == [s.id])

        try await store.markSynced([s.id])
        #expect(try await store.unsynced().isEmpty)

        let found = try await store.sessions(overlapping: DateInterval(start: .at(19, 5), end: .at(20, 0)))
        #expect(found == [s])
    }
}

@Suite struct StretchTests {
    func session(_ id: String, _ from: Date, _ to: Date, device: DeviceKind = .iphone) -> Session {
        Session(device: device, bundleID: id, start: from, end: to, reason: nil)
    }

    @Test func chainsAnyAppsAndRanksByTime() {
        let stretches = StretchBuilder.stretches(in: [
            session("com.apple.MobileSMS", .at(19, 0), .at(19, 1)),
            session("com.burbn.instagram", .at(19, 1, 30), .at(19, 30)),
            session("com.withopal.opal", .at(19, 31), .at(19, 31, 10)),
            session("com.burbn.instagram", .at(19, 31, 10), .at(19, 40)),
            session("com.google.Gmail", .at(21, 0), .at(21, 5)),
        ], device: .iphone)

        #expect(stretches.count == 2)
        #expect(stretches[0].span == 40 * 60)
        #expect(stretches[0].apps.first?.bundleID == "com.burbn.instagram")
        #expect(stretches[0].apps.map(\.bundleID).count == 3)
    }

    @Test func findsEveryBingeInsideAStretch() {
        let sessions = [
            session("com.burbn.instagram", .at(19, 42), .at(19, 42, 30)),
            session("com.burbn.instagram", .at(19, 44), .at(19, 47, 30)),
            session("com.google.Gmail", .at(19, 48), .at(19, 51)),
            session("com.burbn.instagram", .at(19, 52), .at(20, 2)),
            session("com.withopal.opal", .at(20, 3), .at(20, 5)),
            session("com.burbn.instagram", .at(20, 5, 30), .at(20, 17)),
        ]
        let report = ActivityReport(window: DateInterval(start: .at(0, 0), duration: 86_400), sessions: sessions)
        let stretch = try! #require(StretchBuilder.stretches(in: sessions, device: .iphone).first)

        let binges = report.binges(overlapping: stretch)
        let bingeTime: TimeInterval = binges.map(\.activeTime).reduce(0, +)
        #expect(binges.count == 3)
        #expect(bingeTime == 25.5 * 60)
    }

    @Test func dropsGlancesAndOtherDevices() {
        let stretches = StretchBuilder.stretches(in: [
            session("com.apple.mobiletimer", .at(8, 0), .at(8, 0, 5)),
            session("com.apple.Terminal", .at(9, 0), .at(10, 0), device: .mac),
        ], device: .iphone)
        #expect(stretches.isEmpty)
    }
}

@Suite struct LiveLogTests {
    @Test func pairsEventsAfterCutoffAndKeepsOpenAppRunning() {
        let events = [
            start("com.burbn.instagram", .at(18, 0)), end("com.burbn.instagram", .at(18, 20)),
            start("com.burbn.instagram", .at(19, 0)), end("com.burbn.instagram", .at(19, 30)),
            start("com.atebits.Tweetie2", .at(19, 31)),
        ]
        let sessions = LiveLog.sessions(from: events, after: .at(18, 30), now: .at(19, 40))

        #expect(sessions.map(\.bundleID) == ["com.burbn.instagram", "com.atebits.Tweetie2"])
        #expect(sessions.last?.end == .at(19, 40))
    }

    @Test func forgetsAnOpenAppAfterTwoHours() {
        let sessions = LiveLog.sessions(from: [start("com.burbn.instagram", .at(12, 0))], after: .at(0, 0), now: .at(15, 0))
        #expect(sessions.isEmpty)
    }

    @Test func storeRoundTripsLiveEvents() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "scrollback-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SessionStore(url: url)
        try await store.appendLiveEvent(start("com.burbn.instagram", .at(19, 0)))
        try await store.appendLiveEvent(end("com.burbn.instagram", .at(19, 5)))

        let events = try await store.liveEvents(after: .at(18, 0))
        #expect(events.count == 2)
        #expect(events.first?.isStart == true)
    }
}

@Suite struct HistoryTests {
    func report(day: Int, _ sessions: [(String, Date, Date)]) -> ActivityReport {
        let start = Date.at(0, 0, day: day)
        return ActivityReport(
            window: DateInterval(start: start, duration: 86_400),
            sessions: sessions.map { Session(device: .iphone, bundleID: $0.0, start: $0.1, end: $0.2, reason: nil) }
        )
    }

    @Test func cumulativeSplitsSessionsAcrossSlots() {
        let summary = DaySummary(report: report(day: 11, [("com.burbn.instagram", .at(19, 10), .at(19, 40))]), device: .iphone)
        #expect(summary.total == 1800)
        #expect(summary.social == 1800)
        #expect(summary.cumulative[DaySummary.slot(of: .at(19, 14), dayStart: .at(0, 0))] == 300)
        #expect(summary.cumulative[DaySummary.slot(of: .at(19, 29), dayStart: .at(0, 0))] == 1200)
    }

    @Test func baselineIsMedianAndNeedsThreeDays() {
        let days = [10, 30, 50].enumerated().map { index, minutes in
            DaySummary(report: report(day: 5 + index, [("com.burbn.instagram", .at(9, 0, day: 5 + index), .at(9, minutes, day: 5 + index))]), device: .iphone)
        }
        #expect(Baseline(Array(days.prefix(2))) == nil)
        #expect(days.map(\.total) == [600, 1800, 3000])
        let baseline = Baseline(days)
        #expect(baseline != nil)
        #expect(baseline?.cumulative.last == TimeInterval(30 * 60))
    }

    @Test func headlineNamesPeakAndComparison() {
        let today = report(day: 11, [("com.burbn.instagram", .at(21, 0), .at(21, 50))])
        let text = Headline.text(for: today, device: .iphone, baseline: nil, isToday: false)
        #expect(text == "50m of social, mostly 8pm–10pm." || text == "50m of social, mostly 9pm–11pm.")
    }
}

@Suite struct MilestoneTests {
    @Test func backToBackStepsBecomeOneSitting() {
        let sessions = MilestoneTimeline.sessions(from: [
            Milestone(at: .at(19, 0), minutes: 0),
            Milestone(at: .at(19, 30), minutes: 5),
            Milestone(at: .at(19, 35), minutes: 10),
            Milestone(at: .at(19, 41), minutes: 15),
        ])

        #expect(sessions.count == 3)
        #expect(sessions[0].start == .at(19, 25))
        #expect(sessions[1].start == .at(19, 30))
        #expect(sessions[2].start == .at(19, 36))
        #expect(sessions.map(\.duration).reduce(0, +) == TimeInterval(15 * 60))
        #expect(BingeDetector.binges(in: sessions).first?.span == TimeInterval(16 * 60))
    }

    @Test func slowContinuousStepStillChainsWithoutCountingTheWholeGap() {
        let sessions = MilestoneTimeline.sessions(from: [
            Milestone(at: .at(19, 0), minutes: 0),
            Milestone(at: .at(19, 5), minutes: 5),
            Milestone(at: .at(19, 12, 30), minutes: 10),
        ])

        #expect(sessions.count == 2)
        #expect(sessions[1].start == .at(19, 7))
        #expect(sessions[1].duration == 5.5 * 60)
        #expect(BingeDetector.binges(in: sessions).count == 1)
    }

    @Test func ignoresRestartsWhereMinutesGoBackwards() {
        let sessions = MilestoneTimeline.sessions(from: [
            Milestone(at: .at(23, 50), minutes: 40),
            Milestone(at: .at(0, 0, day: 12), minutes: 0),
            Milestone(at: .at(0, 6, day: 12), minutes: 5),
        ])

        #expect(sessions.count == 1)
        #expect(sessions[0].end == .at(0, 6, day: 12))
    }

    @Test func coarseLateStepsKeepTheirFullMinutes() {
        let sessions = MilestoneTimeline.sessions(from: [
            Milestone(at: .at(20, 0), minutes: 240),
            Milestone(at: .at(20, 15), minutes: 255),
            Milestone(at: .at(22, 0), minutes: 270),
        ])

        let total: TimeInterval = sessions.map(\.duration).reduce(0, +)
        #expect(sessions.count == 2)
        #expect(sessions[0].start == .at(20, 0))
        #expect(sessions[1].start == .at(21, 45))
        #expect(total == TimeInterval(30 * 60))
    }
}

@Suite struct DoomscrollNudgeTests {
    /// Steps every 5 minutes from `start`, beginning at `fromMinutes`.
    private func steady(from start: Date, fromMinutes: Int = 0, steps: Int) -> [Milestone] {
        (0...steps).map { Milestone(at: start.addingTimeInterval(TimeInterval($0 * 300)), minutes: fromMinutes + $0 * 5) }
    }

    @Test func nudgesOnceTwentyNonstopMinutesAccrue() {
        let milestones = steady(from: .at(19, 0), steps: 4)
        let fifteen = Array(milestones.dropLast())

        #expect(DoomscrollNudge.due(milestones: fifteen, now: .at(19, 15), lastNudged: nil) == nil)
        let run = DoomscrollNudge.due(milestones: milestones, now: .at(19, 20), lastNudged: nil)
        #expect(run == DoomscrollNudge.Run(start: .at(19, 0), end: .at(19, 20), minutes: 20))
    }

    @Test func eachRunNudgesOnlyOnce() {
        let milestones = steady(from: .at(19, 0), steps: 6)
        #expect(DoomscrollNudge.due(milestones: milestones, now: .at(19, 30), lastNudged: .at(19, 20)) == nil)
    }

    @Test func aBreakStartsANewRun() {
        // 20 minutes, a 10-minute break, then 5 more: the newest run is only the step after the break.
        var milestones = steady(from: .at(19, 0), steps: 4)
        milestones.append(Milestone(at: .at(19, 35), minutes: 25))
        #expect(DoomscrollNudge.currentRun(in: milestones) == DoomscrollNudge.Run(start: .at(19, 30), end: .at(19, 35), minutes: 5))
        #expect(DoomscrollNudge.due(milestones: milestones, now: .at(19, 35), lastNudged: .at(19, 20)) == nil)
    }

    @Test func firstStepAfterABreakCountsInFull() {
        // Use from 18:00 left the count at 10; picking back up around 19:00 reaches 15 at 19:05.
        let milestones = [Milestone(at: .at(18, 0), minutes: 10)] + steady(from: .at(19, 5), fromMinutes: 15, steps: 3)
        let run = DoomscrollNudge.due(milestones: milestones, now: .at(19, 20), lastNudged: nil)
        #expect(run == DoomscrollNudge.Run(start: .at(19, 0), end: .at(19, 20), minutes: 20))
    }

    @Test func aStepFasterThanRealTimeDoesntNudge() {
        // A phantom or premature callback: 5 more minutes after only 1 minute of wall time.
        var milestones = steady(from: .at(19, 0), steps: 3)
        milestones.append(Milestone(at: .at(19, 16), minutes: 20))
        #expect(DoomscrollNudge.due(milestones: milestones, now: .at(19, 16), lastNudged: nil) == nil)
    }

    @Test func phantomStepsInsideARunAreSkipped() {
        // Real steps to 10, a burst of phantoms on the charger, then real use reaches 30 at 19:30.
        var milestones = steady(from: .at(19, 0), steps: 2)
        milestones += [
            Milestone(at: .at(19, 12), minutes: 15),
            Milestone(at: .at(19, 12, 1), minutes: 20),
            Milestone(at: .at(19, 12, 2), minutes: 25),
            Milestone(at: .at(19, 30), minutes: 30),
        ]
        let run = DoomscrollNudge.due(milestones: milestones, now: .at(19, 30), lastNudged: nil)
        #expect(run == DoomscrollNudge.Run(start: .at(19, 0), end: .at(19, 30), minutes: 30))
    }

    @Test func aLateCallbackDoesntSplitTheRun() {
        // The 10-minute step woke the extension 65 seconds late, so the next step looks early.
        let milestones = [
            Milestone(at: .at(19, 0), minutes: 0),
            Milestone(at: .at(19, 5), minutes: 5),
            Milestone(at: .at(19, 11, 5), minutes: 10),
            Milestone(at: .at(19, 15), minutes: 15),
            Milestone(at: .at(19, 20), minutes: 20),
        ]
        let run = DoomscrollNudge.due(milestones: milestones, now: .at(19, 20), lastNudged: nil)
        #expect(run == DoomscrollNudge.Run(start: .at(19, 0), end: .at(19, 20), minutes: 20))
    }

    @Test func duplicateCallbacksDontBreakTheRun() {
        var milestones = steady(from: .at(19, 0), steps: 4)
        milestones.append(Milestone(at: .at(19, 12), minutes: 10))
        milestones.append(Milestone(at: .at(19, 16), minutes: 15))
        let run = DoomscrollNudge.due(milestones: milestones, now: .at(19, 20), lastNudged: nil)
        #expect(run?.start == .at(19, 0))
        #expect(run?.minutes == 20)
    }

    @Test func aLateDuplicateDoesntNudgeAboutAnOldRun() {
        let milestones = steady(from: .at(19, 0), steps: 4) + [Milestone(at: .at(21, 0), minutes: 20)]
        #expect(DoomscrollNudge.due(milestones: milestones, now: .at(21, 0), lastNudged: nil) == nil)
    }

    @Test func stepsWhileLockedDontCount() {
        // Phantom steps at a believable pace while the phone sat locked, then one real step.
        let milestones = steady(from: .at(0, 0, day: 12), steps: 5)
        let run = DoomscrollNudge.due(milestones: milestones, now: .at(0, 25, day: 12), lastNudged: nil, lastLocked: .at(0, 20, day: 12))
        #expect(run == nil)
        #expect(DoomscrollNudge.currentRun(in: milestones, lastLocked: .at(0, 20, day: 12))?.minutes == 5)
    }

    @Test func aRunCarriesAcrossMidnight() {
        // Scrolling from 23:45: steps at 23:50 and 23:55, counting restarts at midnight, then 5 and 10.
        let milestones = [
            Milestone(at: .at(23, 45), minutes: 30),
            Milestone(at: .at(23, 50), minutes: 35),
            Milestone(at: .at(23, 55), minutes: 40),
            Milestone(at: .at(0, 0, day: 12), minutes: 0),
            Milestone(at: .at(0, 5, day: 12), minutes: 5),
            Milestone(at: .at(0, 10, day: 12), minutes: 10),
        ]
        let run = DoomscrollNudge.due(milestones: milestones, now: .at(0, 10, day: 12), lastNudged: nil)
        #expect(run == DoomscrollNudge.Run(start: .at(23, 45), end: .at(0, 10, day: 12), minutes: 25))
    }

    @Test func aRestartAfterABreakStartsANewRun() {
        var milestones = steady(from: .at(19, 0), steps: 3)
        milestones.append(Milestone(at: .at(19, 30), minutes: 0))
        milestones.append(Milestone(at: .at(19, 35), minutes: 5))
        #expect(DoomscrollNudge.currentRun(in: milestones) == DoomscrollNudge.Run(start: .at(19, 30), end: .at(19, 35), minutes: 5))
    }

    @Test func aRunWhoseFirstStepLeftTheLookbackIsntNudgedTwice() {
        // Nudged at 19:20 with the 6:22 step still in view; at 19:25 it's past the lookback.
        let all = [Milestone(at: .at(0, 0), minutes: 0), Milestone(at: .at(6, 22), minutes: 5)] + steady(from: .at(19, 5), fromMinutes: 10, steps: 4)
        #expect(DoomscrollNudge.due(milestones: Array(all.dropLast()), now: .at(19, 20), lastNudged: nil) == DoomscrollNudge.Run(start: .at(19, 0), end: .at(19, 20), minutes: 20))
        let inView = all.filter { $0.at > Date.at(19, 25).addingTimeInterval(-13 * 3600) }
        #expect(DoomscrollNudge.due(milestones: inView, now: .at(19, 25), lastNudged: .at(19, 20)) == nil)
    }

    @Test func aLateCallbackFromBeforeARestartIsIgnored() {
        let milestones = [
            Milestone(at: .at(23, 45), minutes: 30),
            Milestone(at: .at(23, 50), minutes: 35),
            Milestone(at: .at(23, 55), minutes: 40),
            Milestone(at: .at(0, 0, 5, day: 12), minutes: 0),
            Milestone(at: .at(0, 0, 30, day: 12), minutes: 40),
            Milestone(at: .at(0, 5, day: 12), minutes: 5),
            Milestone(at: .at(0, 10, day: 12), minutes: 10),
        ]
        let run = DoomscrollNudge.due(milestones: milestones, now: .at(0, 10, day: 12), lastNudged: nil)
        #expect(run?.start == .at(23, 45))
        #expect(run?.minutes == 25)
    }

    @Test func aPhantomBurstThatMovedTheCountBecomesAnAnchor() {
        // Screen Time's count jumped from 10 to 25 in a burst; later steps are paced from the burst
        // and the burst's minutes aren't counted as use.
        let milestones = steady(from: .at(9, 0), steps: 2) + [
            Milestone(at: .at(9, 12), minutes: 25),
            Milestone(at: .at(9, 17), minutes: 30),
            Milestone(at: .at(9, 22), minutes: 35),
            Milestone(at: .at(9, 27), minutes: 40),
        ]
        #expect(DoomscrollNudge.currentRun(in: milestones) == DoomscrollNudge.Run(start: .at(9, 0), end: .at(9, 27), minutes: 27))
    }

    @Test func coarseLateStepsStillNudge() {
        let milestones = [
            Milestone(at: .at(20, 0), minutes: 240),
            Milestone(at: .at(20, 15), minutes: 255),
            Milestone(at: .at(20, 30), minutes: 270),
        ]
        let run = DoomscrollNudge.due(milestones: milestones, now: .at(20, 30), lastNudged: nil)
        #expect(run == DoomscrollNudge.Run(start: .at(20, 0), end: .at(20, 30), minutes: 30))
    }
}
