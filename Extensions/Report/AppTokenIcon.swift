@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
import ScrollbackCore
import SwiftUI

/// The app's real icon, drawn by Screen Time from its token. Falls back to a category swatch.
struct AppTokenIcon: View {
    let token: ApplicationToken?
    let category: AppCategory
    let size: CGFloat

    var body: some View {
        Group {
            if let token {
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(size / 28)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22).fill(Palette.category(category))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
