import Foundation

/// Apple's Biome segment format (v2): 32-byte header, records growing forward,
/// and a table of 16-byte entries growing backward from the end of the file.
public enum SEGB {
    static let magic: [UInt8] = Array("SEGB".utf8)
    static let headerSize = 32
    static let entrySize = 16
    static let recordPrefixSize = 8

    public enum RecordState: UInt32, Sendable {
        case live = 1
        case deleted = 3
        /// Placeholder entry written when a segment fills up; has no record behind it.
        case unallocated = 4
    }

    public struct Record: Sendable {
        public let state: UInt32
        public let timestamp: Double
        public let payload: [UInt8]

        public var isLive: Bool { state == RecordState.live.rawValue }
    }

    public enum ReadError: Error {
        case notSEGB
        case truncated
    }

    public static func records(in bytes: [UInt8]) throws -> [Record] {
        guard bytes.count >= headerSize, Array(bytes[0..<4]) == magic else { throw ReadError.notSEGB }
        var header = ByteReader(bytes, offset: 4)
        let count = Int(try header.uint32())
        guard headerSize + count * entrySize <= bytes.count else { throw ReadError.truncated }

        var records: [Record] = []
        records.reserveCapacity(count)
        var recordStart = 0
        for index in 0..<count {
            var entry = ByteReader(bytes, offset: bytes.count - entrySize * (index + 1))
            let end = Int(try entry.uint32())
            let state = try entry.uint32()
            let timestamp = Double(bitPattern: try entry.uint64())
            if state == RecordState.unallocated.rawValue { continue }

            let payloadStart = headerSize + recordStart + recordPrefixSize
            let payloadEnd = headerSize + end
            guard payloadStart <= payloadEnd, payloadEnd <= bytes.count else { throw ReadError.truncated }
            records.append(Record(state: state, timestamp: timestamp, payload: Array(bytes[payloadStart..<payloadEnd])))
            recordStart = (end + 3) & ~3
        }
        return records
    }
}
