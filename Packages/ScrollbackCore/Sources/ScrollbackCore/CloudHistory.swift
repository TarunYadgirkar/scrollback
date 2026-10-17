import CryptoKit
import Foundation

/// One UTC day of history, the unit sent through iCloud. UTC keeps the key the same
/// on both devices whatever time zone each is in.
public struct CloudDay: Sendable, Hashable, Comparable {
    public static let length: TimeInterval = 86_400

    public let number: Int64

    public init(number: Int64) {
        self.number = number
    }

    public init(containing date: Date) {
        number = Int64((date.timeIntervalSince1970 / Self.length).rounded(.down))
    }

    public var start: Date { Date(timeIntervalSince1970: Double(number) * Self.length) }
    public var end: Date { Date(timeIntervalSince1970: Double(number + 1) * Self.length) }
    public func contains(_ date: Date) -> Bool { date >= start && date < end }

    public var recordName: String { "day-\(number)" }

    public init?(recordName: String) {
        guard recordName.hasPrefix("day-"), let number = Int64(recordName.dropFirst(4)) else { return nil }
        self.number = number
    }

    public static func < (a: CloudDay, b: CloudDay) -> Bool { a.number < b.number }
}

/// How a day's sessions are packed into a CloudKit record. The packed bytes go in the
/// record's encrypted values, so only this person's devices can read them, not Apple and not us.
public enum CloudHistory {
    public static let containerID = "iCloud.com.tarunyadgirkar.scrollback"
    public static let zoneName = "History"
    public static let recordType = "HistoryDay"
    public static let payloadKey = "payload"
    public static let versionKey = "version"
    public static let version: Int64 = 1
    /// CloudKit caps a record at 1 MB; stay well under it.
    public static let maxPayloadBytes = 900_000

    public enum Failure: Error, Equatable {
        case tooLarge(Int)
        case unreadable
        case newerVersion(Int64)
    }

    public static func pack(_ sessions: [Session]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try encoder.encode(sessions)
        let packed = try (json as NSData).compressed(using: .lzfse) as Data
        guard packed.count <= maxPayloadBytes else { throw Failure.tooLarge(packed.count) }
        return packed
    }

    public static func unpack(_ data: Data, version: Int64) throws -> [Session] {
        guard version <= Self.version else { throw Failure.newerVersion(version) }
        guard let json = try? (data as NSData).decompressed(using: .lzfse) as Data,
              let decoded = try? JSONDecoder().decode([Session].self, from: json)
        else { throw Failure.unreadable }
        // Rebuilt through init so ids always derive from fields, never from the record.
        return decoded.map { Session(device: $0.device, bundleID: $0.bundleID, start: $0.start, end: $0.end, reason: $0.reason) }
    }

    /// Changes whenever anything about the day's sessions does, so unchanged days aren't re-sent.
    public static func digest(of sessions: [Session]) -> String? {
        guard !sessions.isEmpty else { return nil }
        var hasher = SHA256()
        for s in sessions.sorted(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
            let line = "\(s.id)|\(s.end.timeIntervalSince1970)|\(s.reason?.rawValue ?? "")\n"
            hasher.update(data: Data(line.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
