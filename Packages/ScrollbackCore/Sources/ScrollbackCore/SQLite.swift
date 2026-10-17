import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let description: String
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLValue {
    case text(String)
    case real(Double)
    case int(Int64)
    case blob(Data)
    case null
}

struct SQLRow {
    let statement: OpaquePointer

    func text(_ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    func real(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }

    func blob(_ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}

final class SQLiteDatabase {
    private let handle: OpaquePointer

    init(path: String, readOnly: Bool = false) throws {
        var db: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let target = readOnly ? "file:\(path)?mode=ro" : path
        guard sqlite3_open_v2(target, &db, flags | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            throw SQLiteError(description: "\(path): \(message)")
        }
        handle = db
        sqlite3_busy_timeout(db, Self.busyTimeoutMs)
    }

    static let busyTimeoutMs: Int32 = 5_000

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    func run(_ sql: String, _ values: [SQLValue] = []) throws {
        try withStatement(sql, values) { statement in
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
    }

    func query<T>(_ sql: String, _ values: [SQLValue] = [], map: (SQLRow) -> T?) throws -> [T] {
        try withStatement(sql, values) { statement in
            var rows: [T] = []
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { return rows }
                guard step == SQLITE_ROW else { throw lastError() }
                if let row = map(SQLRow(statement: statement)) { rows.append(row) }
            }
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func withStatement<T>(_ sql: String, _ values: [SQLValue], _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            bind(value, at: Int32(index + 1), in: statement)
        }
        return try body(statement)
    }

    private func bind(_ value: SQLValue, at index: Int32, in statement: OpaquePointer) {
        switch value {
        case .text(let s): sqlite3_bind_text(statement, index, s, -1, SQLITE_TRANSIENT)
        case .real(let d): sqlite3_bind_double(statement, index, d)
        case .int(let i): sqlite3_bind_int64(statement, index, i)
        case .blob(let d): _ = d.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), SQLITE_TRANSIENT) }
        case .null: sqlite3_bind_null(statement, index)
        }
    }

    private func lastError() -> SQLiteError {
        SQLiteError(description: String(cString: sqlite3_errmsg(handle)))
    }
}
