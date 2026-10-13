import SwiftUI
import ScrollbackCore

/// Says plainly when recent iPhone activity hasn't arrived yet, so an empty evening doesn't read as "no use".
struct FreshnessNote: View {
    let through: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Palette.inkMuted)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("iPhone activity after \(through.shortClock) hasn't reached your Mac yet")
                    .font(TypeScale.label.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Apple sends it over in batches a few times a day. It'll fill in on its own.")
                    .font(TypeScale.label)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.control))
        .accessibilityElement(children: .combine)
    }
}
