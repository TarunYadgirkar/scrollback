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
    @Environment(\.openWindow) private var openWindow

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
}
