import SwiftUI

struct PairingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Install from your Mac")
                .font(TypeScale.readoutSmall)
                .foregroundStyle(Palette.ink)
            Text("This copy of Scrollback doesn't have your Mac's sync key. Plug your iPhone into your Mac and run scripts/install-phone.sh from the Scrollback folder. It installs a build that already knows your Mac.")
                .font(TypeScale.body)
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface)
    }
}
