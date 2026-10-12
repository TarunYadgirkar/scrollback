import SwiftUI

struct FullDiskAccessView: View {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Let Scrollback read your app history")
                .font(TypeScale.readoutSmall)
                .foregroundStyle(Palette.ink)
            Text("macOS already records which app is in front, on this Mac and on your iPhone through Screen Time's Share Across Devices. That record sits in a protected folder, so macOS asks you to grant Full Disk Access first. Scrollback only reads it, and nothing leaves your devices.")
                .font(TypeScale.body)
                .foregroundStyle(Palette.inkMuted)
                .frame(maxWidth: 480, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.s) {
                step(1, "Open Privacy & Security → Full Disk Access.")
                step(2, "Turn on Scrollback. If it isn't listed, press + and pick it from Applications.")
                step(3, "Come back here and press Check again.")
            }
            HStack(spacing: Space.m) {
                Button("Open Full Disk Access") { NSWorkspace.shared.open(Self.settingsURL) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                Button("Check again", action: onRetry)
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("\(number)").font(TypeScale.mono.weight(.semibold)).foregroundStyle(Palette.inkMuted)
            Text(text).font(TypeScale.body).foregroundStyle(Palette.ink)
        }
    }
}
