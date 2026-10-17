#if os(macOS)
import Foundation

/// Reads App.InFocus from ~/Library/Biome. `local` is this Mac; `remote/<uuid>`
/// holds streams synced from other devices, identified via Biome's sync.db.
public struct BiomeSource: Sendable {
    public enum Failure: Error, LocalizedError {
        case needsFullDiskAccess
        /// Access is fine, but macOS hasn't written an app history stream where Scrollback looks.
        case noAppHistory(String)

        public var errorDescription: String? {
            switch self {
            case .needsFullDiskAccess: "Scrollback needs Full Disk Access to read your app history."
            case .noAppHistory(let path): "macOS hasn't recorded any app history at \(path) yet. Use this Mac for a few minutes, then sync again."
            }
        }
    }

    public struct Result: Sendable {
        public let sessions: [Session]

        /// Window each device's sessions span, so stored history there can be replaced wholesale.
        public func coverage(for device: DeviceKind) -> DateInterval? {
            let mine = sessions.filter { $0.device == device }
            guard let start = mine.map(\.start).min(), let end = mine.map(\.end).max() else { return nil }
            return DateInterval(start: start, end: end)
        }

        /// Files or databases that couldn't be read. Ingest continues without them.
        public let warnings: [String]
    }

    static let iOSPlatform = 2

    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Biome")) {
        self.root = root
    }

    var streamURL: URL { root.appending(path: "streams/restricted/App.InFocus") }
    var screenTimeURL: URL { root.appending(path: "streams/restricted/ScreenTime.AppUsage/local") }

    /// Whether macOS lets this process read Biome's protected streams. Cheap enough to poll while
    /// the user is in System Settings granting Full Disk Access.
    public var hasAccess: Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "streams/restricted").path)
            return true
        } catch {
            return Self.isMissing(error)
        }
    }

    /// A folder that isn't there, as opposed to one macOS won't let us open.
    static func isMissing(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoSuchFileError { return true }
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        return underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(ENOENT)
    }

    public func load() throws -> Result {
        let local = streamURL.appending(path: "local")
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: local.path)
        } catch {
            // Only blame Full Disk Access when the protected folder itself is closed to us; a missing
            // stream inside it would otherwise send the user back to a setting that's already on.
            guard hasAccess, Self.isMissing(error) else { throw Failure.needsFullDiskAccess }
            throw Failure.noAppHistory(local.path)
        }

        // The first warning is the one the app shows, so the actionable ones go first.
        var warnings: [String] = []
        var skipped = 0
        var sessions: [Session] = []
        do {
            let devices = try remoteDevices()
            if devices.isEmpty { warnings.append("No iPhone found in Biome sync. Check that Screen Time's Share Across Devices is on.") }
            for (uuid, kind) in devices {
                sessions += readStream(streamURL.appending(path: "remote/\(uuid)"), device: kind, skipped: &skipped)
            }
        } catch {
            warnings.append("Couldn't read Biome's device list, so iPhone data was skipped.")
        }
        sessions += readMac(fallback: local, warnings: &warnings, skipped: &skipped)
        if skipped > 0 { warnings.append("Skipped \(skipped) unreadable Biome file\(skipped == 1 ? "" : "s").") }
        return Result(sessions: sessions, warnings: warnings)
    }

    /// Screen Time's stream drops idle time; App.InFocus keeps an app "in front" all night if you walk away.
    private func readMac(fallback: URL, warnings: inout [String], skipped: inout Int) -> [Session] {
        let screenTime = readStream(screenTimeURL, device: .mac, decode: FocusEvent.decodeScreenTime, skipped: &skipped)
        if !screenTime.isEmpty { return screenTime }
        warnings.append("Screen Time's usage stream is empty, so Mac time may include idle stretches.")
        return readStream(fallback, device: .mac, skipped: &skipped)
    }

    private func readStream(
        _ directory: URL,
        device: DeviceKind,
        decode: ([UInt8]) throws -> [FocusEvent] = FocusEvent.decode,
        skipped: inout Int
    ) -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var events: [FocusEvent] = []
        for file in files where file.lastPathComponent.allSatisfy(\.isNumber) {
            do {
                events += try decode([UInt8](Data(contentsOf: file)))
            } catch {
                skipped += 1
            }
        }
        return Sessionizer.sessions(from: events, device: device)
    }

    /// Only iPhones are mapped; other synced Macs would double-count with no way to tell them apart in the UI yet.
    func remoteDevices() throws -> [(String, DeviceKind)] {
        let db = try SQLiteDatabase(path: root.appending(path: "sync/sync.db").path, readOnly: true)
        let rows = try db.query("SELECT device_identifier, platform FROM DevicePeer WHERE me = 0") { row in
            row.text(0).map { ($0, Int(row.int(1))) }
        }
        return rows.compactMap { uuid, platform in platform == Self.iOSPlatform ? (uuid, .iphone) : nil }
    }
}
#endif
