import Foundation

public enum DeviceKind: String, Sendable, Codable, CaseIterable {
    case iphone
    case mac
}

public struct Session: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let device: DeviceKind
    public let bundleID: String
    public let start: Date
    public let end: Date
    public let reason: OpenReason?

    public init(device: DeviceKind, bundleID: String, start: Date, end: Date, reason: OpenReason?) {
        self.id = "\(device.rawValue)|\(bundleID)|\(Int(start.timeIntervalSince1970))"
        self.device = device
        self.bundleID = bundleID
        self.start = start
        self.end = end
        self.reason = reason
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var interval: DateInterval { DateInterval(start: start, end: end) }

    public func clipped(to window: DateInterval) -> Session? {
        let s = max(start, window.start)
        let e = min(end, window.end)
        guard e > s else { return nil }
        return Session(device: device, bundleID: bundleID, start: s, end: e, reason: reason)
    }
}

/// Pairs start/end events into sessions. Both iPhone and Mac report one
/// foreground app at a time, so a new start closes whatever is still open.
public enum Sessionizer {
    static let minimumDuration: TimeInterval = 1

    public static func sessions(from events: [FocusEvent], device: DeviceKind) -> [Session] {
        var open: FocusEvent?
        var result: [Session] = []

        func close(at end: Date) {
            guard let start = open else { return }
            open = nil
            guard end.timeIntervalSince(start.date) >= minimumDuration,
                  !AppCatalog.isSystemSurface(start.bundleID)
            else { return }
            result.append(Session(device: device, bundleID: start.bundleID, start: start.date, end: end, reason: start.reason))
        }

        for event in events.sorted(by: { $0.date < $1.date }) {
            if event.isStart {
                if open?.bundleID == event.bundleID { continue }
                close(at: event.date)
                open = event
            } else if open?.bundleID == event.bundleID {
                close(at: event.date)
            }
        }
        return result
    }
}
