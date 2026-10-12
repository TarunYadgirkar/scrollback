import SwiftUI
import ScrollbackCore

/// Maps time to points. Two lanes (iPhone, Mac) and a right margin for binge brackets.
struct RibbonLayout {
    #if os(iOS)
    static let pointsPerMinute: CGFloat = 1.6
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

    var height: CGFloat { y(window.end) }
    var laneWidth: CGFloat { max(0, (width - Self.gutter - Self.laneGap - Self.margin) / 2) }
    var bracketX: CGFloat { Self.gutter + laneWidth * 2 + Self.laneGap + Self.bracketInset }

    func laneX(_ device: DeviceKind) -> CGFloat {
        device == .iphone ? Self.gutter : Self.gutter + laneWidth + Self.laneGap
    }

    func y(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(window.start) / 60) * Self.pointsPerMinute
    }

    func date(atY y: CGFloat) -> Date {
        window.start.addingTimeInterval(TimeInterval(y / Self.pointsPerMinute) * 60)
    }

    func rect(for session: Session) -> CGRect {
        let top = y(session.start)
        return CGRect(x: laneX(session.device), y: top, width: laneWidth, height: max(Self.minBlockHeight, y(session.end) - top))
    }

    func device(atX x: CGFloat) -> DeviceKind? {
        if x >= laneX(.iphone), x < laneX(.iphone) + laneWidth { return .iphone }
        if x >= laneX(.mac), x < laneX(.mac) + laneWidth { return .mac }
        return nil
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
        let slop: CGFloat = 4
        return sessions
            .filter { $0.device == device }
            .filter { let r = rect(for: $0); return point.y >= r.minY - slop && point.y <= r.maxY + slop }
            .min { abs(rect(for: $0).midY - point.y) < abs(rect(for: $1).midY - point.y) }
    }

    func binge(at point: CGPoint, in binges: [Binge]) -> Binge? {
        guard point.x >= bracketX - Self.bracketInset else { return nil }
        return binges.first { point.y >= y($0.start) - 4 && point.y <= max(y($0.end), y($0.start) + Self.bracketLabelHeight) }
    }
}
