import Foundation
import ScrollbackCore

struct PeerProvider: UsageProvider {
    enum Failure: Error {
        case notPaired
    }

    func refresh(into store: SessionStore) async throws -> RefreshResult {
        guard let key = PeerKey.fromBundle() else { throw Failure.notPaired }
        let added = try await PeerClient(key: key).sync(into: store)
        return RefreshResult(added: added, warnings: [])
    }

    func setupNeed(for error: any Error) -> SetupNeed? {
        if case Failure.notPaired = error { return .notPaired }
        return nil
    }
}
