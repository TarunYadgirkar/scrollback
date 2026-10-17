import Combine
import FamilyControls
import Foundation
import Observation
import ScrollbackCore

/// Screen Time permission plus the apps the user counts as doomscrolling.
/// Tokens are opaque: we can show them with `Label(token)` but never learn bundle IDs.
@MainActor @Observable
final class ScreenTimeAccess {
    static let selectionKey = "doomscrollSelection"

    private(set) var status: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    private(set) var lastError: String?
    var selection: FamilyActivitySelection = ScreenTimeAccess.loadSelection() {
        didSet { Self.save(selection) }
    }

    var isApproved: Bool { status == .approved }
    var hasPickedApps: Bool { selection.hasPicks }

    /// Screen Time loads the saved permission a moment after launch, so the first read can say
    /// "not determined" for an app that's approved. Follow Apple's value instead of trusting that read.
    func followStatus() async {
        for await latest in AuthorizationCenter.shared.$authorizationStatus.values {
            status = latest
        }
    }

    func request() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = "Screen Time access wasn't granted: \(error.localizedDescription)"
        }
        status = AuthorizationCenter.shared.authorizationStatus
    }

    static func loadSelection() -> FamilyActivitySelection {
        guard let data = SharedContainer.defaults?.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    private static func save(_ selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        SharedContainer.defaults?.set(data, forKey: selectionKey)
    }
}
