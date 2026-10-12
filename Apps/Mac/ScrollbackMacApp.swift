import SwiftUI
import ScrollbackCore

@main
struct ScrollbackMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Scrollback", id: WindowID.main) {
            MacRoot(model: delegate.model)
                .frame(minWidth: 820, minHeight: 600)
        }
        .defaultSize(width: 1120, height: 860)

        MenuBarExtra {
            MenuBarGlance(model: delegate.model, peerStatus: delegate.peerStatus)
        } label: {
            MenuBarLabel(report: delegate.model.today)
        }
        .menuBarExtraStyle(.window)
    }
}

enum WindowID {
    static let main = "main"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let refreshInterval: Duration = .seconds(5 * 60)

    let model: AppModel
    let peerStatus = PeerStatus()
    private var refreshLoop: Task<Void, Never>?
    private var peerHost: PeerHost?

    override init() {
        do {
            let store = try SessionStore(url: SessionStore.defaultURL())
            model = AppModel(store: store, provider: BiomeProvider())
        } catch {
            fatalError("Couldn't open Scrollback's database at \(SessionStore.defaultURL().path): \(error)")
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshLoop = Task { [model] in
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        peerHost = PeerHost(store: model.store, status: peerStatus)
        peerHost?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MacRoot: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.status == .needsSetup(.fullDiskAccess), !model.hasData {
            FullDiskAccessView { Task { await model.refresh() } }
        } else {
            DayScreen(model: model)
        }
    }
}
