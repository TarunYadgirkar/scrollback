import Foundation
import Observation
import ScrollbackCore

@MainActor @Observable
final class CloudStatus {
    var text = "iCloud sync is starting"
}

/// Sends this Mac's history to the person's private iCloud, so the iPhone gets it away from home.
/// Runs beside the refresh loop, never in it, so a slow iCloud can't hold up reading Biome.
@MainActor
final class CloudHost {
    /// Long enough for a first upload's batches; whatever is left goes on the next run.
    static let timeout: Duration = .seconds(120)

    private let store: SessionStore
    private let status: CloudStatus
    private let uploader = CloudHistoryUploader()
    private var running: Task<Void, Never>?
    /// Set when the person deleted Scrollback's iCloud data; respected until the app next opens.
    private var paused = false

    init(store: SessionStore, status: CloudStatus) {
        self.store = store
        self.status = status
    }

    func uploadInBackground() {
        guard running == nil, !paused else { return }
        running = Task {
            await upload()
            running = nil
        }
    }

    private func upload() async {
        do {
            _ = try await PeerProtocol.withTimeout(Self.timeout, error: CloudSyncError.timedOut) { [store, uploader] in
                try await uploader.upload(from: store)
            }
            status.text = "Saved to iCloud at \(Date.now.formatted(date: .omitted, time: .shortened))"
        } catch CloudSyncError.noAccount {
            status.text = "iCloud sync is off: sign in to iCloud on this Mac"
        } catch CloudSyncError.deletedInSettings {
            paused = true
            status.text = "iCloud history was deleted in Settings. Sync resumes next time Scrollback opens."
        } catch {
            status.text = "iCloud sync stopped: \(error.localizedDescription)"
        }
    }
}
