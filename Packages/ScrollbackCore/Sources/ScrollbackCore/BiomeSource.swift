#if os(macOS)
import Foundation

/// Reads App.InFocus from ~/Library/Biome. `local` is this Mac; `remote/<uuid>`
/// holds streams synced from other devices, identified via Biome's sync.db.
public struct BiomeSource: Sendable {
    public enum Failure: Error {
        case needsFullDiskAccess
    }

    static let iOSPlatform = 2

    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Biome")) {
        self.root = root
    }

    var streamURL: URL { root.appending(path: "streams/restricted/App.InFocus") }

    public func loadSessions() throws -> [Session] {
        guard FileManager.default.isReadableFile(atPath: streamURL.appending(path: "local").path),
              (try? FileManager.default.contentsOfDirectory(atPath: streamURL.appending(path: "local").path)) != nil
        else { throw Failure.needsFullDiskAccess }

        var all = try readStream(streamURL.appending(path: "local"), device: .mac)
        for (uuid, kind) in remoteDevices() {
            all += try readStream(streamURL.appending(path: "remote/\(uuid)"), device: kind)
        }
        return all
    }

    private func readStream(_ directory: URL, device: DeviceKind) throws -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let events = try files
            .filter { $0.lastPathComponent.allSatisfy(\.isNumber) }
            .flatMap { try FocusEvent.decode(segment: [UInt8](Data(contentsOf: $0))) }
        return Sessionizer.sessions(from: events, device: device)
    }

    /// Only iPhones are mapped; other synced Macs would double-count with no way to tell them apart in the UI yet.
    func remoteDevices() -> [(String, DeviceKind)] {
        let path = root.appending(path: "sync/sync.db").path
        guard let db = try? SQLiteDatabase(path: path, readOnly: true) else { return [] }
        let rows = (try? db.query("SELECT device_identifier, platform FROM DevicePeer WHERE me = 0") { row in
            row.text(0).map { ($0, Int(row.int(1))) }
        }) ?? []
        return rows.compactMap { uuid, platform in platform == Self.iOSPlatform ? (uuid, .iphone) : nil }
    }
}
#endif
