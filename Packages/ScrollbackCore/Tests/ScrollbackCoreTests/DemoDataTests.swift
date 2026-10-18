import Foundation
import Testing
@testable import ScrollbackCore

@Suite struct DemoDataTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// Tuesday 2026-10-13, 15:00 in Los Angeles, so yesterday is a weekday.
    private let now = Date(timeIntervalSince1970: 1_791_928_800)

    @Test func sameDaysGiveTheSameSessions() {
        #expect(DemoData.sessions(endingAt: now, calendar: calendar) == DemoData.sessions(endingAt: now, calendar: calendar))
    }

    @Test func stopsAtNow() {
        let sessions = DemoData.sessions(endingAt: now, calendar: calendar)
        #expect(!sessions.isEmpty)
        #expect(sessions.allSatisfy { $0.end <= now })
        #expect(sessions.first.map { $0.start >= calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))! } == true)
    }

    @Test func sessionsOnOneDeviceNeverOverlap() {
        let sessions = DemoData.sessions(endingAt: now, calendar: calendar)
        for device in DeviceKind.allCases {
            let mine = sessions.filter { $0.device == device }
            for (a, b) in zip(mine, mine.dropFirst()) {
                #expect(a.end <= b.start, "\(a.bundleID) overlaps \(b.bundleID)")
            }
        }
    }

    @Test func aFullWeekdayHasBingesAndMacWork() throws {
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
        let day = DateInterval(start: yesterday, duration: 86_400)
        let report = ActivityReport(window: day, sessions: DemoData.sessions(endingAt: now, calendar: calendar))
        #expect(report.binges.filter { $0.device == .iphone }.count >= 2)
        #expect(report.total(on: .mac) > 4 * 3600)
    }

    @Test func everyAppHasARealName() {
        let ids = Set(DemoData.routine.flatMap { $0.steps.map(\.bundleID) })
        #expect(ids.allSatisfy { AppCatalog.known[$0] != nil })
    }
}
