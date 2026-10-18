import Foundation
import ScrollbackCore

/// Launch with `-demo YES` to see a made-up week (DemoData) instead of your own history. It uses a
/// throwaway database and never reads Biome or syncs with the Mac, the iPhone or iCloud.
enum Demo {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demo") }

    static func makeStore() throws -> SessionStore {
        try SessionStore(url: FileManager.default.temporaryDirectory.appending(path: "scrollback-demo-\(UUID().uuidString).sqlite"))
    }
}

struct DemoProvider: UsageProvider {
    func refresh(into store: SessionStore) async throws -> RefreshResult {
        RefreshResult(added: try await store.upsert(DemoData.sessions(endingAt: .now)), warnings: [])
    }

    func setupNeed(for error: any Error) -> SetupNeed? { nil }
}
