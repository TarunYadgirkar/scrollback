import SwiftUI
import ScrollbackCore

/// The day in four numbers. Social time and binges are the only signal-colored values.
struct RecapStrip: View {
    let report: ActivityReport

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.xl) { readouts }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: Space.m) { readouts }
        }
    }

    @ViewBuilder private var readouts: some View {
        Readout(label: "iPhone", value: Format.duration(report.total(on: .iphone)))
        Readout(label: "Social on iPhone", value: Format.duration(report.socialTime(on: .iphone)), isSignal: true)
        if let longest = report.longestBinge {
            Readout(label: "Longest binge", value: Format.duration(longest.span), detail: longest.start.shortClock, isSignal: true)
        } else {
            Readout(label: "Longest binge", value: "None")
        }
        if report.unlocksBeforeSocial > 0 {
            Readout(label: "Opal unlocks → social", value: "\(report.unlocksBeforeSocial)")
        } else {
            Readout(label: "Mac", value: Format.duration(report.total(on: .mac)))
        }
    }
}

struct Readout: View {
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
        .accessibilityElement(children: .combine)
    }
}
