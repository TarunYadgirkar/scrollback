import Foundation
import Testing
@testable import ScrollbackCore

@Suite struct DecodingTests {
    @Test func decodesEventsWithReasons() throws {
        var builder = SEGBBuilder()
        builder.add(start("com.burbn.instagram", .at(19, 0)), transition: "SBSceneLayout:ABC, com.apple.SpringBoard.transitionReason.homescreen")
        builder.add(end("com.burbn.instagram", .at(19, 12, 30)))
        builder.add(start("com.atebits.Tweetie2", .at(19, 12, 31)), transition: "com.apple.SpringBoard.transitionReason.appLibraryCategorySuggested")

        let events = try FocusEvent.decode(segment: builder.build())

        #expect(events.count == 3)
        #expect(events[0] == start("com.burbn.instagram", .at(19, 0), .homeScreen))
        #expect(events[1] == end("com.burbn.instagram", .at(19, 12, 30)))
        #expect(events[2].reason == .appLibrary)
    }

    @Test func skipsDeletedRecords() throws {
        var builder = SEGBBuilder()
        builder.add(start("com.burbn.instagram", .at(19, 0)), state: SEGB.RecordState.deleted.rawValue)
        builder.add(start("com.google.Gmail", .at(19, 5)))

        let events = try FocusEvent.decode(segment: builder.build())

        #expect(events.map(\.bundleID) == ["com.google.Gmail"])
    }

    @Test func skipsUnallocatedTrailingEntry() throws {
        var builder = SEGBBuilder()
        builder.add(start("com.google.Gmail", .at(19, 5)))
        var bytes = builder.build()
        bytes[4] = 2
        let placeholder: [UInt8] = [0, 0, 0, 0, 4, 0, 0, 0] + [UInt8](repeating: 0, count: 8)
        bytes = Array(bytes.dropLast(16)) + placeholder + bytes.suffix(16)

        let events = try FocusEvent.decode(segment: bytes)

        #expect(events.map(\.bundleID) == ["com.google.Gmail"])
    }

    @Test func rejectsNonSEGB() {
        #expect(throws: SEGB.ReadError.self) { try SEGB.records(in: Array("nope, not a segment file".utf8) + [UInt8](repeating: 0, count: 16)) }
    }

    @Test func rejectsEntryCountLargerThanFile() {
        var bytes = SEGBBuilder().build()
        bytes[4] = 0xFF
        #expect(throws: SEGB.ReadError.truncated) { try SEGB.records(in: bytes) }
    }
}

@Suite struct ScreenTimeTests {
    static func payload(_ bundle: String, _ date: Date, isStart: Bool) -> [UInt8] {
        let id = Array(bundle.utf8)
        return [0x08, isStart ? 1 : 0, 0x11] + withUnsafeBytes(of: date.timeIntervalSince1970.bitPattern.littleEndian, Array.init)
            + [0x1A, UInt8(id.count)] + id + [0x28, 0x01]
    }

    @Test func decodesUnixTimestampsAndIdleEnds() throws {
        let start = try #require(FocusEvent(screenTimePayload: Self.payload("com.apple.Terminal", .at(1, 47, 21, day: 12), isStart: true)))
        let end = try #require(FocusEvent(screenTimePayload: Self.payload("com.apple.Terminal", .at(1, 48, 10, day: 12), isStart: false)))

        #expect(start.date == .at(1, 47, 21, day: 12))
        #expect(start.isStart && !end.isStart)
        let sessions = Sessionizer.sessions(from: [start, end], device: .mac)
        #expect(sessions.map(\.duration) == [49])
    }

    @Test func replaceDropsStaleRowsInWindow() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "scrollback-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SessionStore(url: url)
        let inflated = Session(device: .mac, bundleID: "com.apple.Terminal", start: .at(1, 47, day: 12), end: .at(9, 3, day: 12), reason: nil)
        let phone = Session(device: .iphone, bundleID: "com.burbn.instagram", start: .at(2, 0, day: 12), end: .at(2, 10, day: 12), reason: nil)
        try await store.upsert([inflated, phone])

        let corrected = Session(device: .mac, bundleID: "com.apple.Terminal", start: .at(1, 47, day: 12), end: .at(1, 48, day: 12), reason: nil)
        try await store.replace(device: .mac, in: DateInterval(start: .at(0, 0, day: 12), end: .at(12, 0, day: 12)), with: [corrected])

        let all = try await store.sessions(overlapping: DateInterval(start: .at(0, 0, day: 12), end: .at(23, 0, day: 12)))
        #expect(all.count == 2)
        #expect(all.first { $0.device == .mac }?.end == .at(1, 48, day: 12))
    }
}
