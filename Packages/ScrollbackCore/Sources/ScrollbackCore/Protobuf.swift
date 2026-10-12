import Foundation

enum ProtoValue: Sendable {
    case varint(UInt64)
    case fixed64(UInt64)
    case fixed32(UInt32)
    case bytes([UInt8])
}

enum ProtoError: Error {
    case truncated
    case unsupportedWireType(UInt64)
}

struct ProtoMessage: Sendable {
    let fields: [Int: [ProtoValue]]

    init(_ bytes: [UInt8]) throws {
        var reader = ByteReader(bytes)
        var fields: [Int: [ProtoValue]] = [:]
        while !reader.isAtEnd {
            let key = try reader.varint()
            let value = try Self.readValue(wireType: key & 7, from: &reader)
            fields[Int(key >> 3), default: []].append(value)
        }
        self.fields = fields
    }

    private static func readValue(wireType: UInt64, from reader: inout ByteReader) throws -> ProtoValue {
        switch wireType {
        case 0: return .varint(try reader.varint())
        case 1: return .fixed64(try reader.uint64())
        case 2:
            guard let length = Int(exactly: try reader.varint()) else { throw ProtoError.truncated }
            return .bytes(try reader.take(length))
        case 5: return .fixed32(try reader.uint32())
        default: throw ProtoError.unsupportedWireType(wireType)
        }
    }

    func varint(_ field: Int) -> UInt64? {
        guard case .varint(let v) = fields[field]?.first else { return nil }
        return v
    }

    func double(_ field: Int) -> Double? {
        guard case .fixed64(let v) = fields[field]?.first else { return nil }
        return Double(bitPattern: v)
    }

    func string(_ field: Int) -> String? {
        guard case .bytes(let b) = fields[field]?.first else { return nil }
        return String(bytes: b, encoding: .utf8)
    }
}

struct ByteReader {
    private let bytes: [UInt8]
    private(set) var offset: Int

    init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    var isAtEnd: Bool { offset >= bytes.count }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard offset < bytes.count, shift < 64 else { throw ProtoError.truncated }
            let byte = bytes[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte < 0x80 { return result }
            shift += 7
        }
    }

    mutating func take(_ count: Int) throws -> [UInt8] {
        guard count >= 0, count <= bytes.count - offset else { throw ProtoError.truncated }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    mutating func uint32() throws -> UInt32 {
        try take(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func uint64() throws -> UInt64 {
        try take(8).reversed().reduce(0) { $0 << 8 | UInt64($1) }
    }
}
