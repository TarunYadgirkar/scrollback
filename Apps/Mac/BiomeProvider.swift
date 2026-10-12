import Foundation
import ScrollbackCore

struct BiomeProvider: UsageProvider {
    func refresh(into store: SessionStore) async throws -> RefreshResult {
        let result = try await Task.detached(priority: .utility) { try BiomeSource().load() }.value
        var added = try await store.upsert(result.sessions.filter { $0.device == .iphone })
        if let window = result.coverage(for: .mac) {
            added += try await store.replace(device: .mac, in: window, with: result.sessions.filter { $0.device == .mac })
        }
        return RefreshResult(added: added, warnings: result.warnings)
    }

    func setupNeed(for error: any Error) -> SetupNeed? {
        if case BiomeSource.Failure.needsFullDiskAccess = error { return .fullDiskAccess }
        return nil
    }
}
