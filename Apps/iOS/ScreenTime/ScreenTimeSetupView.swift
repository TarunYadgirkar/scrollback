import FamilyControls
import SwiftUI

/// Two steps: allow Screen Time access, then pick the apps that count as doomscrolling.
struct ScreenTimeSetupView: View {
    @Bindable var access: ScreenTimeAccess
    @State private var isPicking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("See your iPhone live")
                .font(TypeScale.readoutSmall)
                .foregroundStyle(Palette.ink)
            Text("With Screen Time access, Scrollback shows today's iPhone use as it happens instead of waiting hours for it to reach your Mac. The data stays on your phone.")
                .font(TypeScale.body)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            step(1, "Allow Screen Time access", done: access.isApproved) {
                Task { await access.request() }
            }
            step(2, access.hasPickedApps ? "Change doomscroll apps" : "Pick your doomscroll apps", done: access.hasPickedApps) {
                isPicking = true
            }
            .disabled(!access.isApproved)

            if let error = access.lastError {
                Text(error).font(TypeScale.label).foregroundStyle(Palette.critical)
            }
        }
        .padding(Space.l)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
        .familyActivityPicker(isPresented: $isPicking, selection: $access.selection)
    }

    private func step(_ number: Int, _ title: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                ZStack {
                    Circle().fill(done ? Palette.messaging : Palette.ink.opacity(0.08)).frame(width: 28, height: 28)
                    if done {
                        Image(systemName: "checkmark").font(TypeScale.label.weight(.bold)).foregroundStyle(.white)
                    } else {
                        Text("\(number)").font(TypeScale.mono.weight(.semibold)).foregroundStyle(Palette.ink)
                    }
                }
                Text(title).font(TypeScale.bodyStrong).foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "chevron.right").font(TypeScale.label).foregroundStyle(Palette.inkFaint)
            }
            .padding(.vertical, Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }
}
