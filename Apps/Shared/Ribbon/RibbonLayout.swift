import SwiftUI
import ScrollbackCore

/// Maps time to points. One lane per visible device, plus a right margin for binge brackets.
struct RibbonLayout {
    #if os(iOS)
    static let pointsPerMinute: CGFloat = 2
    static let gutter: CGFloat = 40
    static let margin: CGFloat = 112
    #else
    static let pointsPerMinute: CGFloat = 2
    static let gutter: CGFloat = 48
    static let margin: CGFloat = 176
    #endif
    static let laneGap: CGFloat = 6
    static let minBlockHeight: CGFloat = 1.5
    static let labelMinHeight: CGFloat = 16
    static let bracketInset: CGFloat = 10
    static let bracketCap: CGFloat = 6
    static let bracketLabelHeight: CGFloat = 46

    let window: DateInterval
    let width: CGFloat
    var devices: [DeviceKind] = DeviceKind.allCases

    var height: CGFloat { y(window.end) }

    var laneWidth: CGFloat {
        let count = CGFloat(max(1, devices.count))
        return max(0, (width - Self.gutter - Self.margin - Self.laneGap * (count - 1)) / count)
    }

    var lanesWidth: CGFloat { laneWidth * CGFloat(devices.count) + Self.laneGap * CGFloat(max(0, devices.count - 1)) }
    var bracketX: CGFloat { Self.gutter + lanesWidth + Self.bracketInset }

    func laneX(_ device: DeviceKind) -> CGFloat? {
        guard let index = devices.firstIndex(of: device) else { return nil }
        return Self.gutter + CGFloat(index) * (laneWidth + Self.laneGap)
    }

    func y(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(window.start) / 60) * Self.pointsPerMinute
    }

    func date(atY y: CGFloat) -> Date {
        window.start.addingTimeInterval(TimeInterval(y / Self.pointsPerMinute) * 60)
    }

    func rect(for session: Session) -> CGRect? {
        guard let x = laneX(session.device) else { return nil }
        let top = y(session.start)
        return CGRect(x: x, y: top, width: laneWidth, height: max(Self.minBlockHeight, y(session.end) - top))
    }

    func device(atX x: CGFloat) -> DeviceKind? {
        devices.first { device in
            guard let lane = laneX(device) else { return false }
            return x >= lane && x < lane + laneWidth
        }
    }

    var hours: [Date] {
        var result: [Date] = []
        var cursor = window.start
        while cursor < window.end {
            result.append(cursor)
            guard let next = Calendar.current.date(byAdding: .hour, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Nearest session in the lane under the point, with a few points of slop so 2-second blips stay tappable.
    func session(at point: CGPoint, in sessions: [Session]) -> Session? {
        guard let device = device(atX: point.x) else { return nil }
        let slop: CGFloat = 6
        let candidates = sessions.compactMap { s -> (Session, CGRect)? in
            guard s.device == device, let r = rect(for: s), point.y >= r.minY - slop, point.y <= r.maxY + slop else { return nil }
            return (s, r)
        }
        return candidates.min { abs($0.1.midY - point.y) < abs($1.1.midY - point.y) }?.0
    }

    func binge(at point: CGPoint, in binges: [Binge]) -> Binge? {
        guard point.x >= bracketX - Self.bracketInset else { return nil }
        return binges.first { devices.contains($0.device) && point.y >= y($0.start) - 4 && point.y <= max(y($0.end), y($0.start) + Self.bracketLabelHeight) }
    }
}
