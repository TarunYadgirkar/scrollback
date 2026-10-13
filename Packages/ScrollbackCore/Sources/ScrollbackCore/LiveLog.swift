import Foundation

/// Turns live open/close events into sessions for the stretch of time Apple's record
/// hasn't covered yet. Once Biome data arrives past a point, live data before it is ignored.
public enum LiveLog {
    public static let retention: TimeInterval = 3 * 86_400
    /// An app opened with no close yet is shown as still open, but not forever (a missed "closed" event).
    public static let maxOpenSession: TimeInterval = 2 * 3600

    public static func sessions(from events: [FocusEvent], after cutoff: Date, now: Date = .now) -> [Session] {
        let recent = events.filter { $0.date > cutoff }.sorted { $0.date < $1.date }
        var sessions = Sessionizer.sessions(from: recent, device: .iphone)
        if let last = recent.last, last.isStart, now.timeIntervalSince(last.date) < maxOpenSession {
            sessions.append(Session(device: .iphone, bundleID: last.bundleID, start: last.date, end: now, reason: nil))
        }
        return sessions
    }
}
