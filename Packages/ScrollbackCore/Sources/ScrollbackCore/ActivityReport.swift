import Foundation

/// Everything that happened in a window, already clipped and summarized.
public struct ActivityReport: Sendable {
    public struct AppTotal: Sendable, Identifiable {
        public let bundleID: String
        public let device: DeviceKind
        public let time: TimeInterval
        public let opens: Int
        public var id: String { "\(device.rawValue)|\(bundleID)" }
        public var name: String { AppCatalog.name(for: bundleID) }
    }

    public let window: DateInterval
    public let sessions: [Session]
    public let binges: [Binge]

    public init(window: DateInterval, sessions: [Session]) {
        self.window = window
        self.sessions = sessions.compactMap { $0.clipped(to: window) }.sorted { $0.start < $1.start }
        self.binges = BingeDetector.binges(in: self.sessions)
    }

    public func total(on device: DeviceKind) -> TimeInterval {
        sessions.filter { $0.device == device }.reduce(0) { $0 + $1.duration }
    }

    public func socialTime(on device: DeviceKind) -> TimeInterval {
        sessions.filter { $0.device == device && AppCatalog.category(for: $0.bundleID) == .social }.reduce(0) { $0 + $1.duration }
    }

    public func apps(on device: DeviceKind) -> [AppTotal] {
        Dictionary(grouping: sessions.filter { $0.device == device }, by: \.bundleID)
            .map { AppTotal(bundleID: $0.key, device: device, time: $0.value.reduce(0) { $0 + $1.duration }, opens: $0.value.count) }
            .sorted { $0.time > $1.time }
    }

    public var longestBinge: Binge? { binges.max { $0.span < $1.span } }

    public func stretches(on device: DeviceKind) -> [Stretch] {
        StretchBuilder.stretches(in: sessions, device: device)
    }

    /// Whether a stretch contains (part of) a binge, for marking it in the list.
    /// A stretch can hold several binges with short breaks between them; all of them count.
    public func binges(overlapping stretch: Stretch) -> [Binge] {
        binges.filter { $0.device == stretch.device && $0.start < stretch.end && stretch.start < $0.end }
    }

    /// Times Opal (or Screen Time) was opened right before a social app.
    public var unlocksBeforeSocial: Int {
        zip(sessions, sessions.dropFirst()).filter { gate, next in
            gate.bundleID == "com.withopal.opal"
                && AppCatalog.category(for: next.bundleID) == .social
                && next.start.timeIntervalSince(gate.end) < 30
        }.count
    }

    /// Each time Opal was opened right before a social app, and how much social time followed in that sitting.
    public var opalBypasses: [(at: Date, socialAfter: TimeInterval)] {
        let stretches = stretches(on: .iphone)
        return zip(sessions, sessions.dropFirst()).compactMap { gate, next in
            guard gate.bundleID == "com.withopal.opal",
                  AppCatalog.category(for: next.bundleID) == .social,
                  next.start.timeIntervalSince(gate.end) < 30,
                  let stretch = stretches.first(where: { $0.sessions.contains(next) })
            else { return nil }
            let after = stretch.sessions
                .filter { $0.start >= next.start && AppCatalog.category(for: $0.bundleID) == .social }
                .reduce(0) { $0 + $1.duration }
            return (next.start, after)
        }
    }

    /// Compact plain-text version for the language model. Short sessions are
    /// folded into totals so the log stays inside the on-device context window.
    public func promptText(maxLogLines: Int = 60) -> String {
        let combined = DeviceKind.allCases.reduce(0) { $0 + total(on: $1) }
        var lines = [
            "Window: \(Format.spokenTime(window.start)) to \(Format.spokenTime(window.end))",
            "Combined screen time across devices: \(Format.duration(combined))",
        ]
        for device in DeviceKind.allCases {
            let apps = apps(on: device)
            guard !apps.isEmpty else {
                lines.append("\(device.rawValue): no usage")
                continue
            }
            let top = apps.prefix(8).map { "\($0.name) \(Format.duration($0.time)) (\($0.opens)x)" }.joined(separator: ", ")
            lines.append("\(device.rawValue) total \(Format.duration(total(on: device))): \(top)")
        }
        if binges.isEmpty {
            lines.append("Doomscroll binges: none")
        } else {
            lines.append("Doomscroll binges (social apps chained, gaps under 2 min):")
            for b in binges {
                let hops = b.hops.map(AppCatalog.name(for:)).joined(separator: " > ")
                lines.append("- \(b.device.rawValue) \(Format.spokenTime(b.start)) to \(Format.spokenTime(b.end)), \(Format.duration(b.span)): \(hops)")
            }
        }
        if unlocksBeforeSocial > 0 { lines.append("Opal unlocks right before a social app: \(unlocksBeforeSocial)") }
        let notable = sessions.filter { $0.duration >= 30 }
        lines.append("Session log (30s or longer\(notable.count > maxLogLines ? ", longest \(maxLogLines) shown" : "")):")
        let shown = notable.count > maxLogLines
            ? notable.sorted { $0.duration > $1.duration }.prefix(maxLogLines).sorted { $0.start < $1.start }
            : notable
        for s in shown {
            lines.append("- \(Format.spokenTime(s.start)) \(s.device.rawValue) \(AppCatalog.name(for: s.bundleID)) \(Format.duration(s.duration))")
        }
        return lines.joined(separator: "\n")
    }
}
