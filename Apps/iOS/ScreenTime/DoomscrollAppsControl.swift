import FamilyControls
import ManagedSettings
import SwiftUI

/// The picked doomscroll apps on the main screen, with a way to change them.
/// A new selection restarts live counting, so picks go to a draft and only Done applies it,
/// and only when the apps actually changed and something is still picked.
struct DoomscrollAppsControl: View {
    private static let shownIcons = 3

    @Bindable var access: ScreenTimeAccess
    @State private var draft = FamilyActivitySelection()
    @State private var isPicking = false

    var body: some View {
        Button {
            draft = access.selection
            isPicking = true
        } label: {
            HStack(spacing: Space.s) {
                Text("Doomscroll apps").font(TypeScale.label).foregroundStyle(Palette.inkMuted).lineLimit(1)
                icons
                Spacer(minLength: Space.s)
                Text("Change").font(TypeScale.label).foregroundStyle(Palette.ink).fixedSize()
                Image(systemName: "chevron.right").font(TypeScale.label).foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Change doomscroll apps")
        .accessibilityValue(summary)
        .sheet(isPresented: $isPicking) { picker }
    }

    /// The embedded picker writes every toggle to the draft, and our own Cancel and Done
    /// decide whether any of it sticks.
    private var picker: some View {
        NavigationStack {
            FamilyActivityPicker(
                headerText: nil,
                footerText: "Changing these restarts live counting. Today's earlier doomscrolling stays; the few minutes since the last step don't count.",
                selection: $draft
            )
            .navigationTitle("Doomscroll apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPicking = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if DoomscrollMonitoring.picksDiffer(draft, access.selection) {
                            access.selection = draft
                        } else {
                            // Starts only if tracking isn't already running these apps.
                            access.retryMonitoring()
                        }
                        isPicking = false
                    }
                    .disabled(!draft.hasPicks)
                }
            }
        }
    }

    private var icons: some View {
        let apps = Array(access.selection.applicationTokens.prefix(Self.shownIcons))
        let categories = Array(access.selection.categoryTokens.prefix(Self.shownIcons - apps.count))
        let hidden = access.selection.applicationTokens.count + access.selection.categoryTokens.count - apps.count - categories.count
        return HStack(spacing: Space.xxs) {
            ForEach(apps, id: \.self) { Label($0).labelStyle(.iconOnly) }
            ForEach(categories, id: \.self) { Label($0).labelStyle(.iconOnly) }
            if hidden > 0 {
                Text("+\(hidden)").font(TypeScale.monoSmall).foregroundStyle(Palette.inkMuted).fixedSize()
            }
        }
        .font(.system(size: 15))
        .accessibilityHidden(true)
    }

    private var summary: String {
        let apps = access.selection.applicationTokens.count
        let categories = access.selection.categoryTokens.count
        var parts: [String] = []
        if apps > 0 { parts.append(apps == 1 ? "1 app" : "\(apps) apps") }
        if categories > 0 { parts.append(categories == 1 ? "1 category" : "\(categories) categories") }
        return parts.joined(separator: ", ")
    }
}

extension FamilyActivitySelection {
    var hasPicks: Bool { !applicationTokens.isEmpty || !categoryTokens.isEmpty }
}
