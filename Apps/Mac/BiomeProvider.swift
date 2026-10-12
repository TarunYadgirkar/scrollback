import Foundation
import ScrollbackCore

struct BiomeProvider: UsageProvider {
    func refresh(into store: SessionStore) async throws -> RefreshResult {
        let result = try await Task.detached(priority: .utility) { try BiomeSource().load() }.value
        let added = try await store.upsert(result.sessions)
        return RefreshResult(added: added, warnings: result.warnings)
    }

    func setupNeed(for error: any Error) -> SetupNeed? {
        if case BiomeSource.Failure.needsFullDiskAccess = error { return .fullDiskAccess }
        return nil
    }
}
