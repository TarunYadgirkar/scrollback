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
