import Combine
import ServiceManagement
import SwiftUI
import ScrollbackCore

struct MenuBarLabel: View {
    let model: AppModel
    let windowRequest: WindowRequest
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let social = model.today.socialTime(on: .iphone)
        HStack(spacing: Space.xs) {
            if needsAccess {
                Image(systemName: "exclamationmark.triangle")
            } else {
                Image(systemName: "hourglass.bottomhalf.filled")
                if social >= 60 { Text(Format.duration(social)).monospacedDigit() }
            }
        }
        .accessibilityLabel(needsAccess ? "Scrollback needs Full Disk Access" : "Social time today \(Format.duration(social))")
        // The label is always on screen, so it's the view that opens the window when AppKit asks.
        .task(id: windowRequest.wantsMain) {
            guard windowRequest.wantsMain else { return }
            windowRequest.wantsMain = false
            openWindow(id: WindowID.main)
            NSApp.activate()
        }
    }

    private var needsAccess: Bool { model.setupNeed == .fullDiskAccess }
}

struct MenuBarGlance: View {
    let model: AppModel
    let peerStatus: PeerStatus
    let cloudStatus: CloudStatus
    let resumeCloudSync: () -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Today").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
            if model.hasData {
                readouts
            } else if model.setupNeed == nil, model.status == .idle || model.status == .syncing {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Reading your app history…").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
                }
            }
            if model.setupNeed == .fullDiskAccess { accessNeeded }
            Rectangle().fill(Palette.rule).frame(height: 1)
            VStack(alignment: .leading, spacing: Space.xs) {
                SyncPill(status: model.status) { Task { await model.refresh() } }
                Text(peerStatus.text)
                    .font(TypeScale.label)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(2)
                    .help(peerStatus.text)
                Text(cloudStatus.text)
                    .font(TypeScale.label)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(2)
                    .help(cloudStatus.text)
                if cloudStatus.isPaused {
                    Button("Turn iCloud sync back on", action: resumeCloudSync).controlSize(.small)
                }
            }
            loginToggle
            HStack {
                Button("Open Scrollback", action: showWindow).keyboardShortcut("o")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .padding(Space.l)
        .frame(width: 300)
        .background(Palette.surface)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    /// This Mac first: its numbers are minutes old, while the iPhone's come through Apple's sync hours late.
    @ViewBuilder private var readouts: some View {
        let today = model.today
        HStack(alignment: .top, spacing: Space.l) {
            Readout(label: "This Mac", value: Format.duration(today.total(on: .mac)))
            Readout(label: "iPhone", value: iPhoneValue)
        }
        Readout(label: "iPhone social", value: Format.duration(today.socialTime(on: .iphone)), isSignal: today.socialTime(on: .iphone) > 0)
        if let freshness = iPhoneFreshness {
            Text(freshness)
                .font(TypeScale.label)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let last = today.binges.last {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Latest binge").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
                BingeReadout(binge: last)
            }
        }
    }

    private var iPhoneValue: String {
        if let stale = model.iPhoneStaleSince, !Calendar.current.isDateInToday(stale), !model.isTrackingLive { return "—" }
        return Format.duration(model.today.total(on: .iphone))
    }

    private var iPhoneFreshness: String? {
        guard let stale = model.iPhoneStaleSince else { return nil }
        guard Calendar.current.isDateInToday(stale) else {
            return "Today's iPhone activity hasn't reached this Mac yet. Apple sends it in batches."
        }
        return model.isTrackingLive
            ? "Social is live. Other iPhone apps are counted up to \(stale.shortClock)."
            : "iPhone numbers stop at \(stale.shortClock). The rest arrives in Apple's next batch."
    }

    @ViewBuilder private var accessNeeded: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.hasData
                ? "Scrollback can't read new history because Full Disk Access is off."
                : "Scrollback needs Full Disk Access to read your app history.")
                .font(TypeScale.label)
                .foregroundStyle(Palette.critical)
                .fixedSize(horizontal: false, vertical: true)
            Button(model.hasData ? "Open Full Disk Access" : "Set Up Scrollback") {
                if model.hasData {
                    NSWorkspace.shared.open(FullDiskAccessView.settingsURL)
                } else {
                    showWindow()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.ink)
            .controlSize(.small)
        }
    }

    @ViewBuilder private var loginToggle: some View {
        Toggle("Open at login", isOn: Binding(get: { loginStatus == .enabled }, set: { setOpensAtLogin($0) }))
            .toggleStyle(.checkbox)
            .font(TypeScale.label)
        if loginStatus == .requiresApproval {
            Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                .controlSize(.small)
        }
        if let loginError {
            Text(loginError).font(TypeScale.label).foregroundStyle(Palette.critical)
        }
    }

    private func showWindow() {
        openWindow(id: WindowID.main)
        NSApp.activate()
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change login item: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
}
