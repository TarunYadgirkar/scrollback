import ScrollbackCore
import SwiftUI

/// Rendered inside the report extension: Apple keeps this data here, so the card draws itself.
struct LiveTodayView: View {
    static let topApps = 5

    let summary: LiveSummary

    nonisolated init(summary: LiveSummary) {
        self.summary = summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            header
            readouts
            apps
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            Circle().fill(Palette.messaging).frame(width: 7, height: 7)
            Text("Live from Screen Time").font(TypeScale.label.weight(.semibold)).foregroundStyle(Palette.ink)
            Spacer()
            if let updated = summary.updated {
                Text("Updated \(updated.shortClock)").font(TypeScale.mono).foregroundStyle(Palette.inkMuted)
            }
        }
    }

    private var readouts: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.m) {
            GridRow {
                LiveReadout(label: "Screen time", value: Format.duration(summary.total))
                LiveReadout(label: "Social apps", value: Format.duration(summary.social), isSignal: summary.social > 0)
            }
            GridRow {
                LiveReadout(label: "Pickups", value: "\(summary.pickups)")
                if let longest = summary.longest {
                    LiveReadout(label: "Longest sitting", value: Format.duration(longest.duration), detail: longest.start.shortClock)
                } else {
                    LiveReadout(label: "Longest sitting", value: "None")
                }
            }
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            let top = summary.apps.prefix(Self.topApps)
            let longest = top.first?.time ?? 1
            ForEach(Array(top)) { app in
                VStack(alignment: .leading, spacing: Space.xxs + 1) {
                    HStack(spacing: Space.s) {
                        AppTokenIcon(token: app.token, category: app.category, size: 22)
                        Text(app.name).font(TypeScale.label).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(app.pickups)×").font(TypeScale.monoSmall).foregroundStyle(Palette.inkFaint)
                        Text(Format.duration(app.time)).font(TypeScale.mono).foregroundStyle(Palette.ink)
                    }
                    GeometryReader { proxy in
                        Capsule().fill(Palette.category(app.category))
                            .frame(width: max(2, proxy.size.width * app.time / longest))
                    }
                    .frame(height: 3)
                }
            }
        }
    }
}

private struct LiveReadout: View {
    let label: String
    let value: String
    var detail: String?
    var isSignal = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(label).font(TypeScale.label).foregroundStyle(Palette.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(value).font(TypeScale.readout).foregroundStyle(isSignal ? Palette.signal : Palette.ink)
                if let detail { Text(detail).font(TypeScale.mono).foregroundStyle(Palette.inkMuted) }
            }
        }
    }
}
