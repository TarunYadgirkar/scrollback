import Foundation

/// A continuous period of using one device: sessions chained with short gaps,
/// whatever the app. "7:23–8:00pm, 37m, mostly Instagram."
public struct Stretch: Sendable, Equatable, Identifiable {
    public struct AppShare: Sendable, Equatable, Identifiable {
        public let bundleID: String
        public let time: TimeInterval
        public var id: String { bundleID }
        public var name: String { AppCatalog.name(for: bundleID) }
        public var category: AppCategory { AppCatalog.category(for: bundleID) }
    }

    public let device: DeviceKind
    public let sessions: [Session]

    public var id: String { sessions.first?.id ?? "" }
    public var start: Date { sessions.first?.start ?? .distantPast }
    public var end: Date { sessions.last?.end ?? .distantPast }
    public var span: TimeInterval { end.timeIntervalSince(start) }
    public var activeTime: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }

    public var apps: [AppShare] {
        Dictionary(grouping: sessions, by: \.bundleID)
            .map { AppShare(bundleID: $0.key, time: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.time > $1.time }
    }

    public var socialTime: TimeInterval {
        sessions.filter { AppCatalog.category(for: $0.bundleID) == .social }.reduce(0) { $0 + $1.duration }
    }
}

public enum StretchBuilder {
    public static let maxGap: TimeInterval = 120
    /// Glances shorter than this (checking the time, dismissing a notification) are left out of the list.
    public static let minimumActive: TimeInterval = 20

    public static func stretches(in sessions: [Session], device: DeviceKind) -> [Stretch] {
        sessions
            .filter { $0.device == device }
            .sorted { $0.start < $1.start }
            .reduce(into: [[Session]]()) { groups, session in
                if let last = groups.last?.last, session.start.timeIntervalSince(last.end) <= maxGap {
                    groups[groups.count - 1].append(session)
                } else {
                    groups.append([session])
                }
            }
            .map { Stretch(device: device, sessions: $0) }
            .filter { $0.activeTime >= minimumActive }
    }
}
