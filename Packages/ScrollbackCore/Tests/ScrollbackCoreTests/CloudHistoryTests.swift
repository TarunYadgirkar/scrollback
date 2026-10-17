import Foundation
import Testing
@testable import ScrollbackCore

// 2025-10-09 00:00 UTC, so day boundaries in these tests don't depend on the machine's time zone.
private let midnight = Date(timeIntervalSince1970: 1_759_968_000)
private let day = CloudDay(containing: midnight)

private func at(_ hours: Double, dayOffset: Double = 0) -> Date {
    midnight.addingTimeInterval((dayOffset * 24 + hours) * 3600)
}

private func session(_ bundleID: String, _ from: Date, _ to: Date, device: DeviceKind = .iphone) -> Session {
    Session(device: device, bundleID: bundleID, start: from, end: to, reason: .notification)
}

private func tempStore() throws -> (SessionStore, URL) {
    let url = FileManager.default.temporaryDirectory.appending(path: "scrollback-cloud-\(UUID()).sqlite")
    return (try SessionStore(url: url), url)
}

@Suite struct CloudDayTests {
    @Test func keysByUTCDay() {
        #expect(CloudDay(containing: at(0)) == day)
        #expect(CloudDay(containing: at(23.99)) == day)
        #expect(CloudDay(containing: at(24)) == CloudDay(number: day.number + 1))
        #expect(day.start == midnight)
        #expect(day.contains(at(12)))
        #expect(!day.contains(at(24)))
    }

    @Test func recordNameRoundTrips() {
        #expect(CloudDay(recordName: day.recordName) == day)
        #expect(CloudDay(recordName: "day-x") == nil)
        #expect(CloudDay(recordName: "night-1") == nil)
    }
}

@Suite struct CloudPayloadTests {
    let sessions = [
        session("com.burbn.instagram", at(19), at(19.5)),
        session("com.apple.Safari", at(20), at(20.25), device: .mac),
    ]

    @Test func packAndUnpackPreserveSessions() throws {
        let unpacked = try CloudHistory.unpack(CloudHistory.pack(sessions), version: CloudHistory.version)
        #expect(unpacked == sessions)
        #expect(unpacked.map(\.id) == sessions.map(\.id))
    }

    @Test func refusesNewerFormatsAndGarbage() throws {
        let packed = try CloudHistory.pack(sessions)
        #expect(throws: CloudHistory.Failure.newerVersion(CloudHistory.version + 1)) {
            try CloudHistory.unpack(packed, version: CloudHistory.version + 1)
        }
        #expect(throws: CloudHistory.Failure.unreadable) { try CloudHistory.unpack(Data("nope".utf8), version: 1) }
    }

    @Test func unknownOpenReasonIsDroppedNotFatal() throws {
        let json = Data(#"[{"id":"x","device":"iphone","bundleID":"com.burbn.instagram","start":0,"end":60,"reason":"someFutureReason"},{"id":"y","device":"vision","bundleID":"a","start":0,"end":60}]"#.utf8)
        let packed = try (json as NSData).compressed(using: .lzfse) as Data
        let unpacked = try CloudHistory.unpack(packed, version: CloudHistory.version)
        #expect(unpacked.count == 1)
        #expect(unpacked[0].reason == nil)
        #expect(unpacked[0].id == "iphone|com.burbn.instagram|\(Int(Date(timeIntervalSinceReferenceDate: 0).timeIntervalSince1970))")
    }

    @Test func digestTracksContentNotOrder() {
        let digest = CloudHistory.digest(of: sessions)
        #expect(digest != nil)
        #expect(CloudHistory.digest(of: sessions.reversed()) == digest)
        let longer = [session("com.burbn.instagram", at(19), at(19.6)), sessions[1]]
        #expect(CloudHistory.digest(of: longer) != digest)
        #expect(CloudHistory.digest(of: []) == nil)
    }
}

@Suite struct CloudStoreTests {
    @Test func writesMarkTheirDaysDirty() async throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try await store.cloudDirtyDays().isEmpty)

        try await store.upsert([session("com.burbn.instagram", at(19), at(19.5)), session("com.burbn.instagram", at(2, dayOffset: 1), at(3, dayOffset: 1))])
        #expect(try await store.cloudDirtyDays() == [day, CloudDay(number: day.number + 1)])
    }

    @Test func uploadClearsDirtyUnlessTheDayChangedMeanwhile() async throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = session("com.burbn.instagram", at(19), at(19.5))
        try await store.upsert([first])
        let digest = CloudHistory.digest(of: try await store.sessions(startingIn: day))

        // A Biome refresh lands between computing the digest and the upload finishing.
        try await store.upsert([session("com.burbn.instagram", at(19), at(19.75))])
        try await store.markCloudUploaded(day, digest: digest, ifStill: digest)
        #expect(try await store.cloudDirtyDays() == [day])
        #expect(try await store.cloudDigest(for: day) == digest)

        let current = CloudHistory.digest(of: try await store.sessions(startingIn: day))
        try await store.markCloudUploaded(day, digest: current, ifStill: current)
        #expect(try await store.cloudDirtyDays().isEmpty)
        #expect(try await store.cloudDigest(for: day) == current)
    }

    @Test func changedRowsRewriteThroughEveryWritePath() async throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try await store.upsert([session("com.burbn.instagram", at(19), at(19.5))])
        try await store.upsert([session("com.burbn.instagram", at(19), at(19.6))])
        try await store.clearCloudDirty(day)
        try await store.upsert([session("com.burbn.instagram", at(19), at(19.7))], markSynced: true)
        #expect(try await store.cloudDirtyDays() == [day])

        try await store.replace(device: .iphone, in: DateInterval(start: at(0), end: at(23)), with: [
            session("com.burbn.instagram", at(19), at(19.8)), session("com.burbn.instagram", at(19), at(19.9)),
        ])
        try await store.replaceCloudDay(day, with: [
            session("com.burbn.instagram", at(19), at(20)), session("com.burbn.instagram", at(19), at(20.1)),
        ])
        #expect(try await store.sessions(startingIn: day).map(\.end) == [at(20.1)])
        #expect(try await store.cloudDirtyDays() == [day])
    }

    @Test func storesWithTheOldTriggersGetTheFixedOnes() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "scrollback-cloud-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try SessionStore(url: url)
        let old = try SQLiteDatabase(path: url.path)
        try old.execute("""
            DROP TRIGGER sessions_cloud_update;
            CREATE TRIGGER sessions_cloud_update AFTER UPDATE ON sessions BEGIN
                INSERT OR IGNORE INTO cloud_dirty (day) VALUES (CAST(OLD.start / 86400 AS INTEGER));
                INSERT OR IGNORE INTO cloud_dirty (day) VALUES (CAST(NEW.start / 86400 AS INTEGER));
            END;
            PRAGMA user_version = 1;
            """)

        let store = try SessionStore(url: url)
        try await store.upsert([session("com.burbn.instagram", at(19), at(19.5))])
        try await store.upsert([session("com.burbn.instagram", at(19), at(19.6))])
        #expect(try await store.cloudDirtyDays() == [day])
    }

    @Test func unchangedRewriteKeepsTheSameDigest() async throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let mac = session("com.apple.Safari", at(9), at(10), device: .mac)
        try await store.upsert([mac])
        let digest = CloudHistory.digest(of: try await store.sessions(startingIn: day))
        try await store.markCloudUploaded(day, digest: digest, ifStill: digest)

        // The Mac's Biome refresh deletes and rewrites its window every five minutes.
        try await store.replace(device: .mac, in: DateInterval(start: at(0), end: at(23)), with: [mac])
        #expect(try await store.cloudDirtyDays() == [day])
        #expect(CloudHistory.digest(of: try await store.sessions(startingIn: day)) == digest)
    }

    @Test func replaceCloudDayKeepsWhatArrivedLaterOverWiFi() async throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let gone = session("com.burbn.instagram", at(9), at(9.5))
        let growing = session("com.apple.Safari", at(10), at(11), device: .mac)
        let later = session("com.atebits.Tweetie2", at(13), at(13.5))
        try await store.upsert([gone, growing, later])

        // The record was packed at noon, when Safari's session was shorter and Twitter hadn't started.
        let shorter = session("com.apple.Safari", at(10), at(10.5), device: .mac)
        try await store.replaceCloudDay(day, with: [shorter], asOf: at(12))
        let kept = try await store.sessions(startingIn: day)
        #expect(kept.map(\.bundleID) == ["com.apple.Safari", "com.atebits.Tweetie2"])
        #expect(kept[0].end == at(11))
    }

    @Test func replaceCloudDayTouchesOnlyThatDay() async throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let stale = session("com.burbn.instagram", at(19), at(19.5))
        let nextDay = session("com.burbn.instagram", at(1, dayOffset: 1), at(2, dayOffset: 1))
        try await store.upsert([stale, nextDay])

        let fresh = session("com.atebits.Tweetie2", at(20), at(20.5), device: .mac)
        // A session from another day in the payload is ignored rather than stored under the wrong key.
        try await store.replaceCloudDay(day, with: [fresh, session("x", at(3, dayOffset: 2), at(4, dayOffset: 2))])
        #expect(try await store.sessions(startingIn: day) == [fresh])
        #expect(try await store.sessions(startingIn: CloudDay(number: day.number + 1)) == [nextDay])
        #expect(try await store.count() == 2)

        try await store.replaceCloudDay(day, with: [])
        #expect(try await store.sessions(startingIn: day).isEmpty)
    }

    @Test func resetSendsEverythingAgain() async throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try await store.upsert([session("com.burbn.instagram", at(19), at(19.5))])
        let digest = CloudHistory.digest(of: try await store.sessions(startingIn: day))
        try await store.markCloudUploaded(day, digest: digest, ifStill: digest)
        try await store.setCloudState("changeToken", Data([1, 2, 3]))
        #expect(try await store.cloudState("changeToken") == Data([1, 2, 3]))

        try await store.resetCloudUploads()
        #expect(try await store.cloudDirtyDays() == [day])
        #expect(try await store.cloudDigest(for: day) == nil)
        #expect(try await store.cloudState("changeToken") == nil)
    }

    @Test func olderStoresQueueTheirWholeHistory() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "scrollback-cloud-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let store = try SessionStore(url: url)
            try await store.upsert([session("com.burbn.instagram", at(19), at(19.5))])
        }
        // Make it look like a store written before iCloud sync existed.
        do {
            let raw = try SQLiteDatabase(path: url.path)
            try raw.execute("DELETE FROM cloud_dirty; PRAGMA user_version = 0;")
        }
        let reopened = try SessionStore(url: url)
        #expect(try await reopened.cloudDirtyDays() == [day])
    }
}
