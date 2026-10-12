import CryptoKit
import Foundation

public enum PeerKeyError: Error, CustomStringConvertible {
    case unreadable(path: String)
    case unwritable(path: String, errno: Int32)

    public var description: String {
        switch self {
        case .unreadable(let path): "Sync key at \(path) is damaged. Delete it and reinstall the iPhone app."
        case .unwritable(let path, let code): "Couldn't save sync key at \(path): \(String(cString: strerror(code)))"
        }
    }
}

public enum PeerKey {
    static let byteCount = 32
    static let infoPlistKey = "ScrollbackPeerKey"

    public static func fromBundle(_ bundle: Bundle = .main) -> SymmetricKey? {
        guard let encoded = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String else { return nil }
        return decode(encoded)
    }

    static func decode(_ base64: String) -> SymmetricKey? {
        let trimmed = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed), data.count == byteCount else { return nil }
        return SymmetricKey(data: data)
    }

    #if os(macOS)
    static let filePermissions: mode_t = 0o600

    public static func defaultURL() -> URL {
        URL.applicationSupportDirectory.appending(path: "Scrollback/peer.key")
    }

    public static func loadOrCreateOnMac(at url: URL = defaultURL()) throws -> SymmetricKey {
        guard FileManager.default.fileExists(atPath: url.path) else { return try create(at: url) }
        // A damaged key is never silently replaced: that would unpair the iPhone.
        guard let key = decode(try String(contentsOf: url, encoding: .utf8)) else { throw PeerKeyError.unreadable(path: url.path) }
        return key
    }

    private static func create(at url: URL) throws -> SymmetricKey {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        let encoded = key.withUnsafeBytes { Data($0) }.base64EncodedString() + "\n"
        // O_EXCL with 0600 so the key is never briefly world-readable and a concurrent creator can't be clobbered.
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, filePermissions)
        guard fd >= 0 else { throw PeerKeyError.unwritable(path: url.path, errno: errno) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: Data(encoded.utf8))
        return key
    }
    #endif
}
