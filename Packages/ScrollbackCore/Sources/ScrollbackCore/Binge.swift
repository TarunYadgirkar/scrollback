import Foundation

/// A run of social-app sessions where each hop happens within `maxGap`, spanning at least
/// `minimumSpan` with at least `minimumActive` of it spent in the apps.
public struct Binge: Sendable, Equatable, Identifiable {
    public let device: DeviceKind
    public let sessions: [Session]

    public var id: String { sessions.first?.id ?? "" }
    public var start: Date { sessions.first?.start ?? .distantPast }
    public var end: Date { sessions.last?.end ?? .distantPast }
    public var span: TimeInterval { end.timeIntervalSince(start) }
    public var activeTime: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }

    /// App order with consecutive repeats collapsed: IG, X, IG, YouTube.
    public var hops: [String] {
        sessions.map(\.bundleID).reduce(into: []) { acc, id in
            if acc.last != id { acc.append(id) }
        }
    }
}

public enum BingeDetector {
    public static let maxGap: TimeInterval = 120
    public static let minimumSpan: TimeInterval = 5 * 60
    /// Without this, a few quick checks two minutes apart (about a minute of use across five) count as a binge.
    public static let minimumActive: TimeInterval = 3 * 60

    public static func binges(
        in sessions: [Session],
        maxGap: TimeInterval = maxGap,
        minimumSpan: TimeInterval = minimumSpan,
        minimumActive: TimeInterval = minimumActive
    ) -> [Binge] {
        let social = sessions
            .filter { AppCatalog.category(for: $0.bundleID) == .social }
            .sorted { $0.start < $1.start }
        return Dictionary(grouping: social, by: \.device)
            .flatMap { device, runs in chain(runs, maxGap: maxGap).map { Binge(device: device, sessions: $0) } }
            .filter { $0.span >= minimumSpan && $0.activeTime >= minimumActive }
            .sorted { $0.start < $1.start }
    }

    private static func chain(_ sessions: [Session], maxGap: TimeInterval) -> [[Session]] {
        sessions.reduce(into: [[Session]]()) { groups, session in
            if let last = groups.last?.last, session.start.timeIntervalSince(last.end) <= maxGap {
                groups[groups.count - 1].append(session)
            } else {
                groups.append([session])
            }
        }
    }
}
