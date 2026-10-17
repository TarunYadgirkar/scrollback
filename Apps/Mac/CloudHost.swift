import Foundation
import Observation
import ScrollbackCore

@MainActor @Observable
final class CloudStatus {
    var text = "iCloud sync is starting"
}

/// Sends this Mac's history to the person's private iCloud, so the iPhone gets it away from home.
@MainActor
final class CloudHost {
    private let store: SessionStore
    private let status: CloudStatus
    private let uploader = CloudHistoryUploader()

    init(store: SessionStore, status: CloudStatus) {
        self.store = store
        self.status = status
    }

    func upload() async {
        do {
            _ = try await uploader.upload(from: store)
            status.text = "Saved to iCloud at \(Date.now.formatted(date: .omitted, time: .shortened))"
        } catch CloudSyncError.noAccount {
            status.text = "iCloud sync is off: sign in to iCloud on this Mac"
        } catch {
            status.text = "iCloud sync stopped: \(error.localizedDescription)"
        }
    }
}
