import SwiftUI
import ScrollbackCore

struct DayHeader: View {
    let model: AppModel
    @State private var isPickingDay = false

    var body: some View {
        HStack(spacing: Space.m) {
            HStack(spacing: Space.xs) {
                stepButton("chevron.left", label: "Previous day", shortcut: .leftArrow, enabled: model.canGoBack) { await model.shift(days: -1) }
                stepButton("chevron.right", label: "Next day", shortcut: .rightArrow, enabled: !model.isToday) { await model.shift(days: 1) }
            }
            Button { isPickingDay = true } label: {
                HStack(spacing: Space.xs) {
                    Text(title).font(TypeScale.title).foregroundStyle(Palette.ink)
                    Image(systemName: "calendar").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("\(title). Pick a day")
            .popover(isPresented: $isPickingDay) { dayPicker }
            if !model.isToday {
                Button { Task { await model.show(day: .now) } } label: {
                    Text("Back to today")
                        .font(TypeScale.label)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.xxs + 1)
                        .background(Palette.raised, in: Capsule())
                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                }
                .buttonStyle(PressScale())
                .keyboardShortcut("t")
            }
            Spacer(minLength: Space.s)
            SyncPill(status: model.status) { Task { await model.refresh() } }
        }
    }

    private var dayPicker: some View {
        DatePicker(
            "Day",
            selection: Binding(get: { model.day }, set: { day in
                isPickingDay = false
                Task { await model.show(day: day) }
            }),
            in: (model.earliestDay ?? model.day)...Date.now,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding(Space.m)
        .frame(minWidth: 300)
        .presentationCompactAdaptation(.popover)
    }

    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(model.day) { return "Today" }
        if cal.isDateInYesterday(model.day) { return "Yesterday" }
        return model.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func stepButton(_ symbol: String, label: String, shortcut: KeyEquivalent, enabled: Bool, action: @escaping @MainActor () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol)
                .font(TypeScale.bodyStrong)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .foregroundStyle(enabled ? Palette.ink : Palette.inkFaint)
        .disabled(!enabled)
        .keyboardShortcut(shortcut, modifiers: [])
        .accessibilityLabel(label)
    }
}

/// Sync state as a dot plus a few words; tap to sync now.
struct SyncPill: View {
    let status: SyncStatus
    let onRefresh: () -> Void

    var body: some View {
        Button(action: onRefresh) {
            HStack(spacing: Space.xs + Space.xxs) {
                if status == .syncing {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                }
                Text(text).font(TypeScale.label).foregroundStyle(Palette.inkMuted).lineLimit(1)
            }
            .padding(.horizontal, Space.s + Space.xxs)
            .padding(.vertical, Space.xs)
            .background(Palette.raised, in: Capsule())
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        }
        .buttonStyle(PressScale())
        .help(helpText)
        .keyboardShortcut("r")
        .accessibilityLabel("\(text). Sync now")
    }

    private var dotColor: Color {
        switch status {
        case .synced(_, let note): note == nil ? Palette.messaging : Palette.inkFaint
        case .failed, .needsSetup: Palette.critical
        case .idle, .syncing: Palette.inkFaint
        }
    }

    private var text: String {
        switch status {
        case .idle: "Not synced yet"
        case .syncing: "Syncing"
        case .synced(let date, _): "Synced \(date.shortClock)"
        case .needsSetup(.fullDiskAccess): "Needs Full Disk Access"
        case .needsSetup(.notPaired): "Not paired with your Mac"
        case .failed: Self.failedText
        }
    }

    #if os(iOS)
    // On the phone, a failed sync almost always means the Mac isn't on the same Wi-Fi.
    static let failedText = "Mac not nearby"
    #else
    static let failedText = "Sync failed"
    #endif

    private var helpText: String {
        switch status {
        case .synced(_, let note?): note
        case .failed(let message): message
        default: "Sync now (⌘R)"
        }
    }
}
