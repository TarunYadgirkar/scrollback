import Combine
import SwiftUI
import ScrollbackCore

@main
struct ScrollbackMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Scrollback", id: WindowID.main) {
            MacRoot(model: delegate.model)
                .frame(minWidth: 820, minHeight: 600)
                .inDockWhileOpen()
        }
        .defaultSize(width: 1120, height: 860)
        // A login launch only puts Scrollback in the menu bar; AppDelegate asks for the window otherwise.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands { ScrollbackCommands(model: delegate.model) }

        MenuBarExtra {
            MenuBarGlance(model: delegate.model, peerStatus: delegate.peerStatus)
        } label: {
            MenuBarLabel(model: delegate.model, windowRequest: delegate.windowRequest)
        }
        .menuBarExtraStyle(.window)
    }
}

enum WindowID {
    static let main = "main"
}

/// AppKit code can't open a SwiftUI window itself, so it leaves a note for a view that can.
@MainActor @Observable
final class WindowRequest {
    var wantsMain = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let refreshInterval: Duration = .seconds(5 * 60)

    let model: AppModel
    let peerStatus = PeerStatus()
    let windowRequest = WindowRequest()
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
        if !Self.launchedAsLoginItem { windowRequest.wantsMain = true }
        refreshLoop = Task { [model, windowRequest] in
            // Show what's already saved while Biome is read, which can take a while.
            await model.reload()
            var isFirst = true
            while !Task.isCancelled {
                await model.refresh()
                // Even a quiet login launch needs the window when there's nothing it can show without setup.
                if isFirst, model.setupNeed == .fullDiskAccess, !model.hasData { windowRequest.wantsMain = true }
                isFirst = false
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        peerHost = PeerHost(store: model.store, status: peerStatus)
        peerHost?.start()
    }

    /// Opening the app again from Finder or Spotlight while it runs in the menu bar brings the window back.
    /// The status item counts as a visible window, so ask regardless; an open window just comes forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        windowRequest.wantsMain = true
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

struct MacRoot: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.setupNeed == .fullDiskAccess, !model.hasData {
                FullDiskAccessView(isChecking: model.status == .syncing) { Task { await model.refresh() } }
            } else if !model.hasData, model.status == .idle || model.status == .syncing {
                FirstReadView()
            } else {
                VStack(spacing: 0) {
                    if model.setupNeed == .fullDiskAccess { AccessLostBanner(model: model) }
                    DayScreen(model: model)
                }
            }
        }
        // Escape lets go of whatever the day is pinned to: a selection, a jump, an answer.
        .background { Button("") { model.clearFocus() }.keyboardShortcut(.cancelAction).hidden() }
    }
}

/// The first Biome read can take a while; an empty day full of zeros would read as "nothing happened".
private struct FirstReadView: View {
    var body: some View {
        VStack(spacing: Space.m) {
            ProgressView()
            Text("Reading your app history…").font(TypeScale.body).foregroundStyle(Palette.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
    }
}

/// Full Disk Access went away after Scrollback already has history, e.g. after a reinstall.
private struct AccessLostBanner: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.critical)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Scrollback can't read new app history").font(TypeScale.bodyStrong).foregroundStyle(Palette.ink)
                Text(detail).font(TypeScale.label).foregroundStyle(Palette.inkMuted)
            }
            Spacer()
            Button("Open Full Disk Access") { NSWorkspace.shared.open(FullDiskAccessView.settingsURL) }
                .buttonStyle(.borderedProminent)
                .tint(Palette.ink)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(Palette.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
    }

    private var detail: String {
        let latest = model.dataThrough.values.max()
        let shown = latest.map { " Showing what was saved up to \($0.formatted(date: .abbreviated, time: .shortened))." } ?? ""
        return "Turn Scrollback back on under Full Disk Access.\(shown)"
    }
}

private extension View {
    /// A Dock icon and menu bar while the window is open; just the menu bar extra otherwise.
    func inDockWhileOpen() -> some View {
        onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}
