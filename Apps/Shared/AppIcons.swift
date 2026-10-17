import SwiftUI
import ScrollbackCore
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

/// Icons for bundle IDs in stored history. Mac apps come from the Mac itself; iPhone apps from
/// Apple's public App Store lookup (only the bundle ID is sent), cached on disk after the first fetch.
@MainActor @Observable
final class AppIcons {
    static let shared = AppIcons()
    nonisolated static let lookupURL = "https://itunes.apple.com/lookup?bundleId="

    private var images: [String: PlatformImage] = [:]
    private var attempted: Set<String> = []

    private var cacheDirectory: URL {
        URL.cachesDirectory.appending(path: "Scrollback/AppIcons")
    }

    func image(for bundleID: String) -> PlatformImage? {
        if let image = images[bundleID] { return image }
        guard !attempted.contains(bundleID), !bundleID.hasPrefix("scrollback.") else { return nil }
        attempted.insert(bundleID)
        Task { await load(bundleID) }
        return nil
    }

    private func load(_ bundleID: String) async {
        let file = cacheDirectory.appending(path: "\(bundleID).png")
        if let data = try? Data(contentsOf: file), let image = PlatformImage(data: data) {
            images[bundleID] = image
            return
        }
        #if os(macOS)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            images[bundleID] = NSWorkspace.shared.icon(forFile: url.path)
            return
        }
        #endif
        guard let data = await Self.fetchStoreIcon(bundleID), let image = PlatformImage(data: data) else { return }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: file)
        images[bundleID] = image
    }

    private nonisolated static func fetchStoreIcon(_ bundleID: String) async -> Data? {
        struct Lookup: Decodable {
            struct Result: Decodable { let artworkUrl100: String? }
            let results: [Result]
        }
        guard let encoded = bundleID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let lookupURL = URL(string: lookupURL + encoded),
              let (data, _) = try? await URLSession.shared.data(from: lookupURL),
              let artwork = try? JSONDecoder().decode(Lookup.self, from: data).results.first?.artworkUrl100,
              let artworkURL = URL(string: artwork),
              let (icon, _) = try? await URLSession.shared.data(from: artworkURL)
        else { return nil }
        return icon
    }
}

/// An app's icon at a fixed size, or its category color while the icon loads or if none exists.
struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let image = AppIcons.shared.image(for: bundleID) {
                #if os(macOS)
                Image(nsImage: image).resizable()
                #else
                Image(uiImage: image).resizable()
                #endif
            } else {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(Palette.category(AppCatalog.category(for: bundleID)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
    }
}
