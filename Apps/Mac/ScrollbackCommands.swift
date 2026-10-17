import SwiftUI
import ScrollbackCore

/// Menu bar commands, so every shortcut is listed somewhere and works wherever focus is.
struct ScrollbackCommands: Commands {
    let model: AppModel

    /// Nothing to browse until the first read has something to show.
    private var canBrowse: Bool { model.hasData }

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            viewToggle(.list, key: "1")
            viewToggle(.timeline, key: "2")
            Divider()
            deviceToggle(.iphone, key: "1")
            deviceToggle(.mac, key: "2")
            Divider()
        }

        CommandMenu("Go") {
            Button("Previous Day") { Task { await model.shift(days: -1) } }
                .keyboardShortcut("[")
                .disabled(!canBrowse || !model.canGoBack)
            Button("Next Day") { Task { await model.shift(days: 1) } }
                .keyboardShortcut("]")
                .disabled(!canBrowse || model.isToday)
            Button("Today") { Task { await model.show(day: .now) } }
                .keyboardShortcut("t")
                .disabled(!canBrowse || model.isToday)
            Divider()
            Button("Ask…") { model.requestAskFocus() }
                .keyboardShortcut("k")
                .disabled(!canBrowse)
            Button("Sync Now") { Task { await model.refresh() } }
                .keyboardShortcut("r")
        }
    }

    private func viewToggle(_ mode: ViewMode, key: KeyEquivalent) -> some View {
        Toggle(mode.label, isOn: Binding(get: { model.viewMode == mode }, set: { if $0 { model.viewMode = mode } }))
            .keyboardShortcut(key, modifiers: .command)
            .disabled(!canBrowse)
    }

    private func deviceToggle(_ device: DeviceKind, key: KeyEquivalent) -> some View {
        Toggle(device.label, isOn: Binding(get: { model.device == device }, set: { if $0 { model.device = device } }))
            .keyboardShortcut(key, modifiers: [.command, .option])
            .disabled(!canBrowse)
    }
}
