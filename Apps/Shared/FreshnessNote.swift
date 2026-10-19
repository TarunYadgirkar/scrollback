import SwiftUI
import ScrollbackCore

/// Says plainly when recent iPhone activity hasn't arrived yet, so an empty evening doesn't read as "no use".
struct FreshnessNote: View {
    let through: Date
    var isLive = false
    /// On the iPhone: the Mac's copy is over a day old, so waiting won't fill it in.
    var macStopped = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: macStopped ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                .foregroundStyle(macStopped ? Palette.critical : Palette.inkMuted)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                    .font(TypeScale.label.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
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

    private var title: String {
        if macStopped { return "Your Mac hasn't sent new history since \(through.dayAndClock)" }
        return isLive ? "Live since \(through.dayAndClock) for tracked apps" : "iPhone activity after \(through.dayAndClock) hasn't reached your Mac yet"
    }

    private var detail: String {
        if macStopped {
            let fix = "Open Scrollback on your Mac and check it's turned on under Full Disk Access."
            return isLive ? "Doomscroll apps are still tracked live here. \(fix)" : fix
        }
        return isLive
            ? "Your doomscroll apps are tracked in 5-minute steps. Everything else fills in when Apple's next batch arrives."
            : "Apple sends it over in batches a few times a day. It'll fill in on its own."
    }
}
