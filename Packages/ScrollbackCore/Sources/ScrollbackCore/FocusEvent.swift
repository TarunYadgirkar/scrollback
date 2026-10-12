import Foundation

public let appleEpochOffset: TimeInterval = 978_307_200

public enum OpenReason: String, Sendable, Codable, CaseIterable {
    case homeScreen = "homescreen"
    case appSwitcher = "appswitcher"
    case appLibrary
    case spotlight
    case widget
    case notification
    case link
    case other

    init(transitionReason raw: String) {
        switch raw {
        case "homescreen": self = .homeScreen
        case "appswitcher": self = .appSwitcher
        case let r where r.hasPrefix("appLibrary"): self = .appLibrary
        case "spotlight": self = .spotlight
        case "widget": self = .widget
        case "notification", "fullScreenAlert": self = .notification
        case "externalrequest", "externalRequest", "breadcrumb": self = .link
        default: self = .other
        }
    }

    public var label: String {
        switch self {
        case .homeScreen: "Home Screen"
        case .appSwitcher: "App Switcher"
        case .appLibrary: "App Library"
        case .spotlight: "Spotlight"
        case .widget: "Widget"
        case .notification: "Notification"
        case .link: "Link"
        case .other: "Other"
        }
    }
}

/// One App.InFocus record: an app came to the foreground or left it.
public struct FocusEvent: Sendable, Equatable {
    public let bundleID: String
    public let date: Date
    public let isStart: Bool
    public let reason: OpenReason?

    public init(bundleID: String, date: Date, isStart: Bool, reason: OpenReason?) {
        self.bundleID = bundleID
        self.date = date
        self.isStart = isStart
        self.reason = reason
    }

    enum Field {
        static let transition = 1
        static let isStart = 3
        static let timestamp = 4
        static let bundleID = 6
    }

    init?(payload: [UInt8]) {
        guard let message = try? ProtoMessage(payload),
              let bundleID = message.string(Field.bundleID),
              let timestamp = message.double(Field.timestamp),
              let startFlag = message.varint(Field.isStart)
        else { return nil }
        self.bundleID = bundleID
        self.date = Date(timeIntervalSince1970: timestamp + appleEpochOffset)
        self.isStart = startFlag == 1
        self.reason = message.string(Field.transition).flatMap(Self.parseReason)
    }

    private static func parseReason(_ transition: String) -> OpenReason? {
        guard let range = transition.range(of: "transitionReason.") else { return nil }
        let raw = transition[range.upperBound...].prefix { $0.isLetter }
        return raw.isEmpty ? nil : OpenReason(transitionReason: String(raw))
    }

    public static func decode(segment bytes: [UInt8]) throws -> [FocusEvent] {
        try SEGB.records(in: bytes).filter(\.isLive).compactMap { FocusEvent(payload: $0.payload) }
    }

    /// ScreenTime.AppUsage records: same start/end idea as App.InFocus, but Apple
    /// ends the session when the Mac goes idle, and timestamps are Unix seconds.
    enum ScreenTimeField {
        static let isStart = 1
        static let timestamp = 2
        static let bundleID = 3
    }

    init?(screenTimePayload payload: [UInt8]) {
        guard let message = try? ProtoMessage(payload),
              let bundleID = message.string(ScreenTimeField.bundleID),
              let timestamp = message.double(ScreenTimeField.timestamp),
              let startFlag = message.varint(ScreenTimeField.isStart)
        else { return nil }
        self.init(bundleID: bundleID, date: Date(timeIntervalSince1970: timestamp), isStart: startFlag == 1, reason: nil)
    }

    public static func decodeScreenTime(segment bytes: [UInt8]) throws -> [FocusEvent] {
        try SEGB.records(in: bytes).filter(\.isLive).compactMap { FocusEvent(screenTimePayload: $0.payload) }
    }
}
