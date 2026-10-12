import Foundation
@testable import ScrollbackCore

/// Builds synthetic SEGB v2 files so tests never depend on real Biome data.
struct SEGBBuilder {
    private var records: [(state: UInt32, payload: [UInt8])] = []

    mutating func add(_ event: FocusEvent, transition: String? = nil, state: UInt32 = 1) {
        records.append((state, Self.payload(for: event, transition: transition)))
    }

    func build() -> [UInt8] {
        var body: [UInt8] = []
        var entries: [[UInt8]] = []
        for record in records {
            body += [0, 0, 0, 0, 10, 0, 0, 0] + record.payload
            let end = UInt32(body.count)
            while body.count % 4 != 0 { body.append(0) }
            entries.append(le(end) + le(record.state) + le(UInt64(0)))
        }
        let header = Array("SEGB".utf8) + le(UInt32(records.count)) + [UInt8](repeating: 0, count: 24)
        return header + body + entries.reversed().flatMap { $0 }
    }

    static func payload(for event: FocusEvent, transition: String?) -> [UInt8] {
        var out: [UInt8] = []
        if let transition {
            let bytes = Array(transition.utf8)
            out += [0x0A] + varint(UInt64(bytes.count)) + bytes
        }
        out += [0x10, 0x01, 0x18, event.isStart ? 1 : 0]
        out += [0x21] + le((event.date.timeIntervalSince1970 - appleEpochOffset).bitPattern)
        let bundle = Array(event.bundleID.utf8)
        out += [0x32] + varint(UInt64(bundle.count)) + bundle
        return out
    }

    private static func varint(_ value: UInt64) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        repeat {
            let byte = UInt8(v & 0x7F)
            v >>= 7
            out.append(v == 0 ? byte : byte | 0x80)
        } while v != 0
        return out
    }
}

private func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian, Array.init)
}

extension Date {
    static func at(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 11) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m, second: s))!
    }
}

func start(_ id: String, _ date: Date, _ reason: OpenReason? = nil) -> FocusEvent {
    FocusEvent(bundleID: id, date: date, isStart: true, reason: reason)
}

func end(_ id: String, _ date: Date) -> FocusEvent {
    FocusEvent(bundleID: id, date: date, isStart: false, reason: nil)
}
