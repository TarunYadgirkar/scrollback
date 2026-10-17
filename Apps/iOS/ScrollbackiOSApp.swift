import FamilyControls
import SwiftUI
import ScrollbackCore
import WidgetKit

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
                    // Free while the app is in front, so the widget catches up with anything the monitor's reloads missed.
                    WidgetCenter.shared.reloadTimelines(ofKind: SharedContainer.doomscrollWidgetKind)
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

    // The simulator can't grant Screen Time, so let it reach the synced history.
    private var needsScreenTimeSetup: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        !access.isApproved || !access.hasPickedApps
        #endif
    }

    var body: some View {
        Group {
            if needsScreenTimeSetup {
                ScrollView {
                    ScreenTimeSetupView(access: access).padding(Space.l)
                }
                .background(Palette.surface)
            } else if model.status == .needsSetup(.notPaired), !model.hasData {
                PairingView()
            } else {
                DayScreen(model: model)
                    .environment(\.screenTimeToday, AnyView(ScreenTimeTodayCard()))
                    .environment(\.doomscrollApps, AnyView(DoomscrollAppsControl(access: access)))
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
        .task { await access.followStatus() }
        // Re-runs when approval arrives after launch, when the picked apps change, and on a retry from Done.
        .task(id: MonitoringKey(selection: access.isApproved ? access.selection : nil, retries: access.monitoringRetries)) {
            guard access.isApproved, access.hasPickedApps else { return }
            do {
                try await DoomscrollMonitoring.startIfNeeded(access.selection)
                monitorError = nil
            } catch {
                monitorError = "Couldn't start live tracking: \(error.localizedDescription)"
            }
        }
    }
}

private struct MonitoringKey: Equatable {
    let selection: FamilyActivitySelection?
    let retries: Int
}
