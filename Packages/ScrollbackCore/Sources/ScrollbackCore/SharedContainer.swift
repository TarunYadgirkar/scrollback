import Foundation

/// The App Group shared by the iPhone app and its Screen Time extensions, so the
/// monitor extension can write usage events the app reads.
public enum SharedContainer {
    public static let appGroupID = "group.com.example.scrollback"

    public static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    public static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

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
