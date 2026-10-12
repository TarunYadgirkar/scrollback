import Foundation

/// Local copy of every session ever seen. Apple prunes Biome after a few
/// weeks; this store is what keeps history from expiring.
public actor SessionStore {
    private let db: SQLiteDatabase

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try SQLiteDatabase(path: url.path)
        try db.execute("""
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                device TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                start REAL NOT NULL,
                end REAL NOT NULL,
                reason TEXT,
                synced INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS sessions_start ON sessions(start);
            CREATE INDEX IF NOT EXISTS sessions_unsynced ON sessions(synced) WHERE synced = 0;
            """)
    }

    public static func defaultURL() -> URL {
        URL.applicationSupportDirectory.appending(path: "Scrollback/sessions.sqlite")
    }

    /// Inserts new sessions. An existing row is only rewritten (and marked
    /// unsynced) when its end time or open reason actually changed.
    @discardableResult
    public func upsert(_ sessions: [Session], markSynced: Bool = false) throws -> Int {
        let before = try count()
        try db.transaction {
            for s in sessions {
                try db.run("""
                    INSERT INTO sessions (id, device, bundle_id, start, end, reason, synced)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET end = excluded.end, reason = excluded.reason, synced = excluded.synced
                    WHERE sessions.end != excluded.end OR sessions.reason IS NOT excluded.reason
                    """, Self.values(for: s) + [.int(markSynced ? 1 : 0)])
            }
        }
        return try count() - before
    }

    public func sessions(overlapping window: DateInterval) throws -> [Session] {
        try db.query(
            "SELECT id, device, bundle_id, start, end, reason FROM sessions WHERE start < ? AND end > ? ORDER BY start",
            [.real(window.end.timeIntervalSince1970), .real(window.start.timeIntervalSince1970)],
            map: Self.session(from:)
        )
    }

    public func sessions(endingAfter date: Date) throws -> [Session] {
        try db.query(
            "SELECT id, device, bundle_id, start, end, reason FROM sessions WHERE end >= ? ORDER BY start",
            [.real(date.timeIntervalSince1970)],
            map: Self.session(from:)
        )
    }

    public func unsynced(limit: Int = 500) throws -> [Session] {
        try db.query(
            "SELECT id, device, bundle_id, start, end, reason FROM sessions WHERE synced = 0 ORDER BY start LIMIT ?",
            [.int(Int64(limit))],
            map: Self.session(from:)
        )
    }

    public func markSynced(_ ids: [String]) throws {
        try db.transaction {
            for id in ids {
                try db.run("UPDATE sessions SET synced = 1 WHERE id = ?", [.text(id)])
            }
        }
    }

    public func latestEnd() throws -> Date? {
        try db.query("SELECT MAX(end) FROM sessions") { row in
            row.real(0) > 0 ? Date(timeIntervalSince1970: row.real(0)) : nil
        }.first
    }

    public func earliestStart() throws -> Date? {
        try db.query("SELECT MIN(start) FROM sessions") { row in
            row.real(0) > 0 ? Date(timeIntervalSince1970: row.real(0)) : nil
        }.first
    }

    public func count() throws -> Int {
        try db.query("SELECT COUNT(*) FROM sessions") { Int($0.int(0)) }.first ?? 0
    }

    private static func values(for s: Session) -> [SQLValue] {
        [
            .text(s.id), .text(s.device.rawValue), .text(s.bundleID),
            .real(s.start.timeIntervalSince1970), .real(s.end.timeIntervalSince1970),
            s.reason.map { .text($0.rawValue) } ?? .null,
        ]
    }

    private static func session(from row: SQLRow) -> Session? {
        guard let device = row.text(1).flatMap(DeviceKind.init(rawValue:)), let bundleID = row.text(2) else { return nil }
        return Session(
            device: device,
            bundleID: bundleID,
            start: Date(timeIntervalSince1970: row.real(3)),
            end: Date(timeIntervalSince1970: row.real(4)),
            reason: row.text(5).flatMap(OpenReason.init(rawValue:))
        )
    }
}
