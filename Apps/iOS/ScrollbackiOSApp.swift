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
    @State private var access = ScreenTimeAccess()
    @State private var monitorError: String?

    var body: some View {
        Group {
            if !access.isApproved || !access.hasPickedApps {
                ScrollView {
                    ScreenTimeSetupView(access: access).padding(Space.l)
                }
                .background(Palette.surface)
            } else if model.status == .needsSetup(.notPaired), !model.hasData {
                PairingView()
            } else {
                DayScreen(model: model)
                    .environment(\.liveToday, AnyView(LiveTodayCard()))
            }
        }
        .overlay(alignment: .bottom) {
            if let monitorError {
                Text(monitorError)
                    .font(TypeScale.label)
                    .foregroundStyle(Palette.critical)
                    .padding(Space.m)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.control))
                    .padding(Space.l)
            }
        }
        .task(id: access.isApproved) {
            guard access.isApproved else { return }
            await ActivityProbe.run()
        }
        .task(id: access.selection) {
            guard access.isApproved, access.hasPickedApps else { return }
            do {
                try await DoomscrollMonitoring.start(access.selection)
            } catch {
                monitorError = "Couldn't start live tracking: \(error.localizedDescription)"
            }
        }
    }
}
