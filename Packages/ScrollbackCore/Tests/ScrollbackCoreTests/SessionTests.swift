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
        ], stepMinutes: 5)

        #expect(sessions.count == 3)
        #expect(sessions[0].start == .at(19, 25))
        #expect(sessions[1].start == .at(19, 30))
        #expect(sessions[2].start == .at(19, 35))
        #expect(BingeDetector.binges(in: sessions).first?.span == TimeInterval(16 * 60))
    }

    @Test func ignoresRestartsWhereMinutesGoBackwards() {
        let sessions = MilestoneTimeline.sessions(from: [
            Milestone(at: .at(23, 50), minutes: 40),
            Milestone(at: .at(0, 0, day: 12), minutes: 0),
            Milestone(at: .at(0, 6, day: 12), minutes: 5),
        ], stepMinutes: 5)

        #expect(sessions.count == 1)
        #expect(sessions[0].end == .at(0, 6, day: 12))
    }
}
