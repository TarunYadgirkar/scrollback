import SwiftUI
import ScrollbackCore

/// The selected device's day in a few numbers. Social time and binges are the only signal-colored values.
struct RecapStrip: View {
    let report: ActivityReport
    let device: DeviceKind

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.xl) { readouts }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: Space.m) { readouts }
        }
    }

    private var binges: [Binge] { report.binges.filter { $0.device == device } }
    private var stretches: [Stretch] { report.stretches(on: device) }

    @ViewBuilder private var readouts: some View {
        Readout(label: "Screen time", value: Format.duration(report.total(on: device)))
        Readout(label: "Social apps", value: Format.duration(report.socialTime(on: device)), isSignal: report.socialTime(on: device) > 0)
        if let longest = binges.max(by: { $0.activeTime < $1.activeTime }) {
            Readout(label: "Longest binge", value: Format.duration(longest.activeTime), detail: longest.start.shortClock, isSignal: true)
        } else if let longest = stretches.max(by: { $0.span < $1.span }) {
            Readout(label: "Longest stretch", value: Format.duration(longest.span), detail: longest.start.shortClock)
        } else {
            Readout(label: "Longest binge", value: "None")
        }
        if device == .iphone, report.unlocksBeforeSocial > 0 {
            Readout(label: "Got past Opal", value: "\(report.unlocksBeforeSocial)×")
        } else {
            Readout(label: device == .iphone ? "Pickups" : "Sittings", value: "\(stretches.count)")
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
