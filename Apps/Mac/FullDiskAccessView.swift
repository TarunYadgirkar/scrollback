import Combine
import SwiftUI
import ScrollbackCore

struct FullDiskAccessView: View {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    static let pollInterval: Duration = .seconds(2)

    var isChecking = false
    let onRetry: () -> Void
    @State private var checkedWithoutAccess = false

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
                step(2, "Turn on Scrollback. If it isn't listed, press Show in Finder and drag Scrollback into the list.")
                step(3, "Come back here. Scrollback notices the change by itself.")
            }
            HStack(spacing: Space.m) {
                Button("Open Full Disk Access") { NSWorkspace.shared.open(Self.settingsURL) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                    .buttonStyle(.bordered)
                Button("Check Again", action: checkNow)
                    .buttonStyle(.bordered)
                    .disabled(isChecking)
                if isChecking { ProgressView().controlSize(.small) }
            }
            .controlSize(.large)
            if checkedWithoutAccess { stillBlocked }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
        // Watch for the switch in System Settings instead of waiting on a button press.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                if BiomeSource().hasAccess { return onRetry() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if BiomeSource().hasAccess { onRetry() }
        }
    }

    /// The switch is on but macOS hasn't applied it to the running app, or an old copy of Scrollback is the one listed.
    private var stillBlocked: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Still no access. If Scrollback is already switched on, quit and reopen it, or remove it from the list with − and add it again.")
                .font(TypeScale.label)
                .foregroundStyle(Palette.critical)
                .frame(maxWidth: 480, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button("Quit and Reopen", action: relaunch).buttonStyle(.bordered)
        }
    }

    private func checkNow() {
        checkedWithoutAccess = !BiomeSource().hasAccess
        onRetry()
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("\(number)").font(TypeScale.mono.weight(.semibold)).foregroundStyle(Palette.inkMuted)
            Text(text).font(TypeScale.body).foregroundStyle(Palette.ink)
        }
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
