import Foundation
import ScrollbackCore

/// History comes from the Mac two ways: its iCloud copy (anywhere) and the Mac itself (same Wi-Fi).
struct PeerProvider: UsageProvider {
    enum Failure: Error {
        case notPaired
    }

    func refresh(into store: SessionStore) async throws -> RefreshResult {
        var added = 0
        var warnings: [String] = []
        var cloudWorked = false
        // iCloud first: it replaces whole days, and the Mac's live answer then lays newer rows on top.
        do {
            if let pulled = try await CloudHistoryDownloader().pull(into: store) {
                added += pulled
                cloudWorked = true
            }
        } catch CloudSyncError.noAccount {
            // Not signed in to iCloud: Wi-Fi sync alone, as before.
        } catch {
            warnings.append("iCloud sync failed: \(error.localizedDescription)")
        }

        guard let key = PeerKey.fromBundle() else {
            if cloudWorked { return RefreshResult(added: added, warnings: warnings) }
            throw Failure.notPaired
        }
        do {
            added += try await PeerClient(key: key).sync(into: store)
        } catch let error as PeerSyncError where cloudWorked && (error == .notFound || error == .timedOut) {
            // Away from the Mac's Wi-Fi: say how fresh the iCloud copy is, since the Mac may be asleep.
            if let saved = await CloudHistoryDownloader.lastMacSave(in: store) {
                warnings.append("Mac not nearby. Showing what it saved to iCloud at \(saved.formatted(date: .abbreviated, time: .shortened)).")
            } else {
                warnings.append("Mac not nearby. Showing its iCloud copy.")
            }
        }
        return RefreshResult(added: added, warnings: warnings)
    }

    func setupNeed(for error: any Error) -> SetupNeed? {
        if case Failure.notPaired = error { return .notPaired }
        return nil
    }
}
