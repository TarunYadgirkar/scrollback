#if os(macOS)
import Foundation

/// Reads App.InFocus from ~/Library/Biome. `local` is this Mac; `remote/<uuid>`
/// holds streams synced from other devices, identified via Biome's sync.db.
public struct BiomeSource: Sendable {
    public enum Failure: Error {
        case needsFullDiskAccess
    }

    public struct Result: Sendable {
        public let sessions: [Session]
        /// Files or databases that couldn't be read. Ingest continues without them.
        public let warnings: [String]
    }

    static let iOSPlatform = 2

    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Biome")) {
        self.root = root
    }

    var streamURL: URL { root.appending(path: "streams/restricted/App.InFocus") }

    public func load() throws -> Result {
        let local = streamURL.appending(path: "local")
        guard (try? FileManager.default.contentsOfDirectory(atPath: local.path)) != nil else { throw Failure.needsFullDiskAccess }

        var warnings: [String] = []
        var sessions = readStream(local, device: .mac, warnings: &warnings)
        do {
            let devices = try remoteDevices()
            if devices.isEmpty { warnings.append("No iPhone found in Biome sync. Check that Screen Time's Share Across Devices is on.") }
            for (uuid, kind) in devices {
                sessions += readStream(streamURL.appending(path: "remote/\(uuid)"), device: kind, warnings: &warnings)
            }
        } catch {
            warnings.append("Couldn't read the device list, so iPhone data was skipped: \(error)")
        }
        return Result(sessions: sessions, warnings: warnings)
    }

    private func readStream(_ directory: URL, device: DeviceKind, warnings: inout [String]) -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var events: [FocusEvent] = []
        for file in files where file.lastPathComponent.allSatisfy(\.isNumber) {
            do {
                events += try FocusEvent.decode(segment: [UInt8](Data(contentsOf: file)))
            } catch {
                warnings.append("Skipped \(directory.lastPathComponent)/\(file.lastPathComponent): \(error)")
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
