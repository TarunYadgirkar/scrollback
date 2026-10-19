import ScrollbackCore
import SwiftUI

/// Every app used on the phone today, most used first, one card each. Scrolls itself for the
/// same reason as the Today view: touches on a Screen Time report never reach the app.
struct LiveAppsView: View {
    let summary: LiveSummary

    nonisolated init(summary: LiveSummary) {
        self.summary = summary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(summary.apps.count) apps").font(TypeScale.bodyStrong).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(Format.duration(summary.total)).font(TypeScale.mono).foregroundStyle(Palette.inkMuted)
                }
                if summary.apps.isEmpty {
                    Text("No app use yet today.").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
                }
                let longest = max(summary.apps.first?.time ?? 1, 1)
                ForEach(summary.apps) { app in
                    LiveAppRow(app: app, share: app.time / longest)
                }
            }
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
    }
}

private struct LiveAppRow: View {
    let app: LiveSummary.App
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                AppTokenIcon(token: app.token, category: app.category, size: 28)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(app.name).font(TypeScale.bodyStrong).foregroundStyle(Palette.ink).lineLimit(1)
                    Text("\(app.category.label) · picked up \(app.pickups)×")
                        .font(TypeScale.label)
                        .foregroundStyle(Palette.inkMuted)
                }
                Spacer(minLength: Space.s)
                Text(Format.duration(app.time))
                    .font(TypeScale.readoutSmall)
                    .foregroundStyle(app.category == .social ? Palette.signal : Palette.ink)
            }
            GeometryReader { proxy in
                Capsule().fill(Palette.category(app.category))
                    .frame(width: max(2, proxy.size.width * share))
            }
            .frame(height: 4)
        }
        .padding(Space.m)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
    }
}
