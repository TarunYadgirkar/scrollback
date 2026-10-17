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
            CREATE TABLE IF NOT EXISTS live_events (
                bundle_id TEXT NOT NULL,
                at REAL NOT NULL,
                is_start INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS live_events_at ON live_events(at);
            CREATE TABLE IF NOT EXISTS milestones (
                at REAL NOT NULL,
                minutes INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS milestones_at ON milestones(at);
            CREATE TABLE IF NOT EXISTS cloud_dirty (day INTEGER PRIMARY KEY);
            CREATE TABLE IF NOT EXISTS cloud_days (day INTEGER PRIMARY KEY, digest TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS cloud_state (key TEXT PRIMARY KEY, value BLOB NOT NULL);
            """)
        // The app and the monitor extension can open the store at the same moment, so each
        // step re-reads the version inside its own write transaction.
        try Self.migrate(db, to: 1, """
            INSERT OR IGNORE INTO cloud_dirty (day) SELECT DISTINCT CAST(start / 86400 AS INTEGER) FROM sessions;
            """)
        try Self.migrate(db, to: 2, """
            DROP TRIGGER IF EXISTS sessions_cloud_insert;
            DROP TRIGGER IF EXISTS sessions_cloud_update;
            DROP TRIGGER IF EXISTS sessions_cloud_delete;
            \(Self.cloudTriggers)
            """)
    }

    private static func migrate(_ db: SQLiteDatabase, to version: Int64, _ sql: String) throws {
        func current() throws -> Int64 { try db.query("PRAGMA user_version", map: { $0.int(0) }).first ?? 0 }
        guard try current() < version else { return }
        try db.transaction {
            guard try current() < version else { return }
            try db.execute(sql + "\nPRAGMA user_version = \(version);")
        }
    }

    /// An upsert's conflict policy overrides OR IGNORE inside a trigger, so these dedupe with NOT EXISTS.
    private static let cloudTriggers = """
        CREATE TRIGGER sessions_cloud_insert AFTER INSERT ON sessions BEGIN
            INSERT INTO cloud_dirty (day) SELECT CAST(NEW.start / 86400 AS INTEGER)
            WHERE NOT EXISTS (SELECT 1 FROM cloud_dirty WHERE day = CAST(NEW.start / 86400 AS INTEGER));
        END;
        CREATE TRIGGER sessions_cloud_update AFTER UPDATE ON sessions BEGIN
            INSERT INTO cloud_dirty (day) SELECT CAST(OLD.start / 86400 AS INTEGER)
            WHERE NOT EXISTS (SELECT 1 FROM cloud_dirty WHERE day = CAST(OLD.start / 86400 AS INTEGER));
            INSERT INTO cloud_dirty (day) SELECT CAST(NEW.start / 86400 AS INTEGER)
            WHERE NOT EXISTS (SELECT 1 FROM cloud_dirty WHERE day = CAST(NEW.start / 86400 AS INTEGER));
        END;
        CREATE TRIGGER sessions_cloud_delete AFTER DELETE ON sessions BEGIN
            INSERT INTO cloud_dirty (day) SELECT CAST(OLD.start / 86400 AS INTEGER)
            WHERE NOT EXISTS (SELECT 1 FROM cloud_dirty WHERE day = CAST(OLD.start / 86400 AS INTEGER));
        END;
        """

    public static func defaultURL() -> URL {
        #if os(iOS)
        if let shared = SharedContainer.url {
            let url = shared.appending(path: "Library/Application Support/Scrollback/sessions.sqlite")
            SharedContainer.moveLegacyStore(from: legacyURL, to: url)
            return url
        }
        #endif
        return legacyURL
    }

    static var legacyURL: URL { URL.applicationSupportDirectory.appending(path: "Scrollback/sessions.sqlite") }

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

    /// Swaps every stored session for `device` that starts inside `window` for `sessions`.
    /// Used when a better source re-derives a stretch of history, so stale rows don't linger beside new ones.
    @discardableResult
    public func replace(device: DeviceKind, in window: DateInterval, with sessions: [Session]) throws -> Int {
        let before = try count()
        try db.transaction {
            try db.run(
                "DELETE FROM sessions WHERE device = ? AND start >= ? AND start <= ?",
                [.text(device.rawValue), .real(window.start.timeIntervalSince1970), .real(window.end.timeIntervalSince1970)]
            )
            for s in sessions {
                try db.run("""
                    INSERT INTO sessions (id, device, bundle_id, start, end, reason, synced) VALUES (?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(id) DO UPDATE SET end = excluded.end, reason = excluded.reason, synced = 0
                    """, Self.values(for: s))
            }
        }
        return try count() - before
    }

    /// Records an open/close the moment it happens on the phone (from a Shortcuts automation),
    /// long before Apple's own record reaches the Mac.
    public func appendLiveEvent(_ event: FocusEvent) throws {
        try db.run(
            "INSERT INTO live_events (bundle_id, at, is_start) VALUES (?, ?, ?)",
            [.text(event.bundleID), .real(event.date.timeIntervalSince1970), .int(event.isStart ? 1 : 0)]
        )
        try db.run("DELETE FROM live_events WHERE at < ?", [.real(event.date.addingTimeInterval(-LiveLog.retention).timeIntervalSince1970)])
    }

    public func appendMilestone(_ milestone: Milestone) throws {
        try db.run("INSERT INTO milestones (at, minutes) VALUES (?, ?)", [.real(milestone.at.timeIntervalSince1970), .int(Int64(milestone.minutes))])
        try db.run("DELETE FROM milestones WHERE at < ?", [.real(milestone.at.addingTimeInterval(-LiveLog.retention).timeIntervalSince1970)])
    }

    public func milestones(after date: Date) throws -> [Milestone] {
        try db.query("SELECT at, minutes FROM milestones WHERE at > ? ORDER BY at", [.real(date.timeIntervalSince1970)]) { row in
            Milestone(at: Date(timeIntervalSince1970: row.real(0)), minutes: Int(row.int(1)))
        }
    }

    public func liveEvents(after date: Date) throws -> [FocusEvent] {
        try db.query("SELECT bundle_id, at, is_start FROM live_events WHERE at > ? ORDER BY at", [.real(date.timeIntervalSince1970)]) { row in
            row.text(0).map { FocusEvent(bundleID: $0, date: Date(timeIntervalSince1970: row.real(1)), isStart: row.int(2) == 1, reason: nil) }
        }
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

    public func latestEnd(for device: DeviceKind) throws -> Date? {
        try db.query("SELECT MAX(end) FROM sessions WHERE device = ?", [.text(device.rawValue)]) { row in
            row.real(0) > 0 ? Date(timeIntervalSince1970: row.real(0)) : nil
        }.first
    }

    public func earliestStart() throws -> Date? {
        try db.query("SELECT MIN(start) FROM sessions") { row in
            row.real(0) > 0 ? Date(timeIntervalSince1970: row.real(0)) : nil
        }.first
    }

    // MARK: iCloud history

    /// Days whose sessions changed since they were last sent to iCloud.
    public func cloudDirtyDays() throws -> [CloudDay] {
        try db.query("SELECT day FROM cloud_dirty ORDER BY day") { CloudDay(number: $0.int(0)) }
    }

    /// Every stored session that starts inside `day`, all devices.
    public func sessions(startingIn day: CloudDay) throws -> [Session] {
        try db.query(
            "SELECT id, device, bundle_id, start, end, reason FROM sessions WHERE start >= ? AND start < ? ORDER BY start, id",
            [.real(day.start.timeIntervalSince1970), .real(day.end.timeIntervalSince1970)],
            map: Self.session(from:)
        )
    }

    public func cloudDigest(for day: CloudDay) throws -> String? {
        try db.query("SELECT digest FROM cloud_days WHERE day = ?", [.int(day.number)]) { $0.text(0) }.first
    }

    /// Records what iCloud now holds for `day` (nil when its record was deleted) and clears
    /// the dirty mark, unless the day changed again after `digest` was computed.
    public func markCloudUploaded(_ day: CloudDay, digest: String?, ifStill current: String?) throws {
        try db.transaction {
            if let digest {
                try db.run("INSERT INTO cloud_days (day, digest) VALUES (?, ?) ON CONFLICT(day) DO UPDATE SET digest = excluded.digest", [.int(day.number), .text(digest)])
            } else {
                try db.run("DELETE FROM cloud_days WHERE day = ?", [.int(day.number)])
            }
            if try CloudHistory.digest(of: sessions(startingIn: day)) == current {
                try db.run("DELETE FROM cloud_dirty WHERE day = ?", [.int(day.number)])
            }
        }
    }

    public func clearCloudDirty(_ day: CloudDay) throws {
        try db.run("DELETE FROM cloud_dirty WHERE day = ?", [.int(day.number)])
    }

    /// Forgets what iCloud holds, so every day is sent again (after the zone was deleted). The
    /// signed-in account is kept, so a pause set right after this survives the next account check.
    public func resetCloudUploads() throws {
        try db.execute("""
            DELETE FROM cloud_days;
            DELETE FROM cloud_state WHERE key <> 'account';
            INSERT OR IGNORE INTO cloud_dirty (day) SELECT DISTINCT CAST(start / 86400 AS INTEGER) FROM sessions;
            """)
    }

    /// Makes `day` match what the Mac sent through iCloud as of `asOf`, for the part of it the
    /// Mac's store reaches back to (`coversFrom`). Rows that start after `asOf`, end times that
    /// grew past `asOf` over Wi-Fi, and rows older than the Mac's reach are kept.
    @discardableResult
    public func replaceCloudDay(_ day: CloudDay, with sessions: [Session], asOf: Date = .distantFuture, coversFrom: Date = .distantPast) throws -> Int {
        let before = try count()
        let incoming = sessions.filter { day.contains($0.start) }
        let ids = String(decoding: try JSONEncoder().encode(incoming.map(\.id)), as: UTF8.self)
        try db.transaction {
            // Rows the record carries are left for the upsert below.
            try db.run(
                "DELETE FROM sessions WHERE start >= ? AND start < ? AND start <= ? AND id NOT IN (SELECT value FROM json_each(?))",
                [.real(max(day.start, coversFrom).timeIntervalSince1970), .real(day.end.timeIntervalSince1970), .real(min(asOf, day.end).timeIntervalSince1970), .text(ids)]
            )
            for s in incoming {
                try db.run("""
                    INSERT INTO sessions (id, device, bundle_id, start, end, reason, synced) VALUES (?, ?, ?, ?, ?, ?, 1)
                    ON CONFLICT(id) DO UPDATE SET
                        end = CASE WHEN sessions.end > ? THEN MAX(sessions.end, excluded.end) ELSE excluded.end END,
                        reason = excluded.reason, synced = 1
                    """, Self.values(for: s) + [.real(asOf.timeIntervalSince1970)])
            }
        }
        return try count() - before
    }

    /// Adds sessions this store doesn't have yet, leaving existing rows exactly as they are.
    @discardableResult
    public func insertMissing(_ sessions: [Session]) throws -> Int {
        let before = try count()
        try db.transaction {
            for s in sessions {
                try db.run(
                    "INSERT INTO sessions (id, device, bundle_id, start, end, reason, synced) VALUES (?, ?, ?, ?, ?, ?, 0) ON CONFLICT(id) DO NOTHING",
                    Self.values(for: s)
                )
            }
        }
        return try count() - before
    }

    public func cloudState(_ key: String) throws -> Data? {
        try db.query("SELECT value FROM cloud_state WHERE key = ?", [.text(key)]) { $0.blob(0) }.first
    }

    public func setCloudState(_ key: String, _ value: Data?) throws {
        if let value {
            try db.run("INSERT INTO cloud_state (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [.text(key), .blob(value)])
        } else {
            try db.run("DELETE FROM cloud_state WHERE key = ?", [.text(key)])
        }
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
