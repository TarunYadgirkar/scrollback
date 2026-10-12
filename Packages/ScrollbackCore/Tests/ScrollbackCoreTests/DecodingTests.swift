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
