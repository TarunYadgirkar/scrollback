import Foundation

/// The App Group shared by the iPhone app and its Screen Time extensions, so the
/// monitor extension can write usage events the app reads.
public enum SharedContainer {
    /// From the target's Info.plist, which gets it from Config/Base.xcconfig. Nil in targets without the App Group.
    public static let appGroupID = BuildConfig.value(for: "ScrollbackAppGroup")

    public static var url: URL? {
        appGroupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    public static var defaults: UserDefaults? { appGroupID.flatMap { UserDefaults(suiteName: $0) } }

    /// Where the app keeps the doomscroll apps it's monitoring. Versioned with the ladder, so a new ladder
    /// restarts monitoring once instead of waiting for a new pick. The widgets read it to tell "not set up" from "0m".
    public static let monitoredSelectionKey = "monitoredSelection.v2"

    /// The doomscroll widget's kind, so the monitor and the app can ask it to redraw.
    public static let doomscrollWidgetKind = "DoomscrollToday"
    /// When the monitor last asked the doomscroll widget to redraw. Those reloads spend a small daily budget,
    /// so they're spaced about `widgetReloadSpacing` apart. Only the monitor writes it: the widget's own
    /// reloads (app opens, catch-ups) mustn't make the monitor skip a step nothing else will pick up.
    public static let widgetReloadedAtKey = "widgetReloadedAt"
    public static let widgetReloadSpacing: TimeInterval = 15 * 60

    /// Builds before the App Group kept the database in the app's own container. Move it once.
    static func moveLegacyStore(from legacy: URL, to shared: URL) {
        let fm = FileManager.default
        guard legacy != shared, fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: shared.path) else { return }
        try? fm.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(filePath: legacy.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.moveItem(at: from, to: URL(filePath: shared.path + suffix))
        }
    }
}
