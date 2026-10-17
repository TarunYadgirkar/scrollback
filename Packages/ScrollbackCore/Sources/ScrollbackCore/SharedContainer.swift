import Foundation

/// The App Group shared by the iPhone app and its Screen Time extensions, so the
/// monitor extension can write usage events the app reads.
public enum SharedContainer {
    public static let appGroupID = "group.com.tarunyadgirkar.scrollback"

    public static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    public static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// Where the app keeps the doomscroll apps it's monitoring. Versioned with the ladder, so a new ladder
    /// restarts monitoring once instead of waiting for a new pick. The widgets read it to tell "not set up" from "0m".
    public static let monitoredSelectionKey = "monitoredSelection.v2"

    /// The doomscroll widget's kind, so the monitor and the app can ask it to redraw.
    public static let doomscrollWidgetKind = "DoomscrollToday"
    /// When the doomscroll widget last redrew. Reloads from the extensions spend a small daily budget,
    /// so they're spaced at least `widgetReloadSpacing` apart.
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
