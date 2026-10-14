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
            HourStrip(hours: summary.hours)
            apps
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    HStack {
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

/// 24 columns, social stacked on everything else. One glance answers "when was I on my phone".
private struct HourStrip: View {
    static let height: CGFloat = 56

    let hours: [LiveSummary.Hour]

    var body: some View {
        let peak = max(hours.map { $0.social + $0.other }.max() ?? 0, 60)
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { index in
                    let hour = hours.first { Calendar.current.component(.hour, from: $0.start) == index }
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(Palette.idle).frame(height: Self.height * (hour?.other ?? 0) / peak)
                        Rectangle().fill(Palette.signal).frame(height: Self.height * (hour?.social ?? 0) / peak)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Palette.ink.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                }
            }
            .frame(height: Self.height)
            HStack {
                ForEach(["12am", "6am", "12pm", "6pm"], id: \.self) { label in
                    Text(label).font(TypeScale.monoSmall).foregroundStyle(Palette.inkFaint)
                    if label != "6pm" { Spacer() }
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Use by hour")
    }
}
