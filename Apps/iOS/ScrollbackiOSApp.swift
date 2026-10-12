import SwiftUI
import ScrollbackCore

@main
struct ScrollbackiOSApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let store = try SessionStore(url: SessionStore.defaultURL())
            _model = State(initialValue: AppModel(store: store, provider: PeerProvider()))
        } catch {
            fatalError("Couldn't open Scrollback's database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            IOSRoot(model: model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await model.reload()
                        await model.refresh()
                    }
                }
        }
    }
}

struct IOSRoot: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.status == .needsSetup(.notPaired), !model.hasData {
            PairingView()
        } else {
            DayScreen(model: model)
        }
    }
}
