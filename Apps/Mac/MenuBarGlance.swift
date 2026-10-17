import ServiceManagement
import SwiftUI
import ScrollbackCore

struct MenuBarLabel: View {
    let report: ActivityReport

    var body: some View {
        let social = report.socialTime(on: .iphone)
        HStack(spacing: Space.xs) {
            Image(systemName: "hourglass.bottomhalf.filled")
            if social >= 60 { Text(Format.duration(social)).monospacedDigit() }
        }
        .accessibilityLabel("Social time today \(Format.duration(social))")
    }
}

struct MenuBarGlance: View {
    let model: AppModel
    let peerStatus: PeerStatus
    let cloudStatus: CloudStatus
    @Environment(\.openWindow) private var openWindow
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        let today = model.today
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Today").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
            HStack(alignment: .top, spacing: Space.l) {
                Readout(label: "iPhone", value: Format.duration(today.total(on: .iphone)))
                Readout(label: "Social", value: Format.duration(today.socialTime(on: .iphone)), isSignal: true)
            }
            if let last = today.binges.last {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Latest binge").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
                    BingeReadout(binge: last)
                }
            }
            Rectangle().fill(Palette.rule).frame(height: 1)
            VStack(alignment: .leading, spacing: Space.xs) {
                SyncPill(status: model.status) { Task { await model.refresh() } }
                Text(peerStatus.text).font(TypeScale.label).foregroundStyle(Palette.inkMuted)
                Text(cloudStatus.text).font(TypeScale.label).foregroundStyle(Palette.inkMuted)
            }
            Toggle("Open at login", isOn: $opensAtLogin)
                .toggleStyle(.checkbox)
                .font(TypeScale.label)
                .onChange(of: opensAtLogin) { _, enabled in setOpensAtLogin(enabled) }
            if let loginError {
                Text(loginError).font(TypeScale.label).foregroundStyle(Palette.critical)
            }
            HStack {
                Button("Open Scrollback") {
                    openWindow(id: WindowID.main)
                    NSApp.activate()
                }
                .keyboardShortcut("o")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .padding(Space.l)
        .frame(width: 300)
        .background(Palette.surface)
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change login item: \(error.localizedDescription)"
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
