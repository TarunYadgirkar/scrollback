import Foundation
import ScrollbackCore

/// Tells whether the phone is unlocked, from inside an extension that has no UIApplication.
/// The app writes a file only readable while unlocked; a threshold that fires while it's unreadable
/// can't be someone scrolling (Screen Time fires phantom thresholds on the charger).
enum LockProbe {
    private static var url: URL? { SharedContainer.url?.appending(path: "unlock-probe") }

    /// Called by the app, which only runs unlocked. Cheap enough to call on every launch.
    static func install() {
        guard let url, !FileManager.default.fileExists(atPath: url.path) else { return }
        try? Data("unlocked".utf8).write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// False only when the probe exists and can't be read. Without a probe we can't tell, so assume unlocked.
    static var isUnlocked: Bool {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return true }
        return (try? Data(contentsOf: url)) != nil
    }
}
