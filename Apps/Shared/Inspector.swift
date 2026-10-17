import SwiftUI
import ScrollbackCore

/// Right-hand column on the Mac: the day in numbers, binges to jump to, then where the time went.
struct Inspector: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                RecapStrip(report: model.report, device: model.device)
                if let lag = model.iPhoneLag { FreshnessNote(through: lag, isLive: model.isTrackingLive) }
                BingeList(model: model)
                TopApps(device: model.device, apps: model.report.apps(on: model.device))
            }
            .padding(Space.l)
        }
        .scrollIndicators(.never)
    }
}

struct BingeList: View {
    let model: AppModel

    private var binges: [Binge] { model.report.binges.filter { $0.device == model.device } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(text: "Binges", detail: binges.isEmpty ? nil : "\(binges.count)")
            if binges.isEmpty {
                Text("No binges this day.")
                    .font(TypeScale.label).foregroundStyle(Palette.inkMuted)
            }
            ForEach(binges.reversed()) { binge in
                Button {
                    model.selection = .binge(binge)
                    Task { await model.focus(on: DateInterval(start: binge.start, end: binge.end)) }
                } label: {
                    BingeRow(binge: binge, isSelected: model.selection == .binge(binge))
                }
                .buttonStyle(PressScale())
            }
        }
    }
}

private struct BingeRow: View {
    let binge: Binge
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            RoundedRectangle(cornerRadius: 1.5).fill(Palette.signal).frame(width: 3)
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.duration(binge.span)).font(TypeScale.readoutSmall).foregroundStyle(Palette.signal)
                    Spacer()
                    Text(binge.start.shortClock).font(TypeScale.mono).foregroundStyle(Palette.inkMuted)
                }
                Text(binge.hops.map(AppCatalog.name(for:)).joined(separator: " → "))
                    .font(TypeScale.label).foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(Space.s)
        .background(isSelected ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: Radius.control))
        .shadow(color: .black.opacity(isSelected ? 0.06 : 0), radius: 3, y: 1)
        .contentShape(Rectangle())
    }
}

struct TopApps: View {
    static let limit = 8

    let device: DeviceKind
    let apps: [ActivityReport.AppTotal]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(text: "Top apps", detail: Format.duration(apps.reduce(0) { $0 + $1.time }))
            if apps.isEmpty {
                Text("No usage recorded.").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
            }
            let longest = apps.first?.time ?? 1
            ForEach(apps.prefix(Self.limit)) { app in
                VStack(alignment: .leading, spacing: Space.xxs + 1) {
                    HStack {
                        AppIconView(bundleID: app.bundleID, size: 18)
                        Text(app.name).font(TypeScale.label).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(app.opens)×").font(TypeScale.monoSmall).foregroundStyle(Palette.inkFaint)
                        Text(Format.duration(app.time)).font(TypeScale.mono).foregroundStyle(Palette.ink)
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                    GeometryReader { proxy in
                        Capsule().fill(Palette.category(AppCatalog.category(for: app.bundleID)))
                            .frame(width: max(2, proxy.size.width * app.time / longest))
                    }
                    .frame(height: 3)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(TypeScale.bodyStrong).foregroundStyle(Palette.ink)
            Spacer()
            if let detail { Text(detail).font(TypeScale.mono).foregroundStyle(Palette.inkMuted) }
        }
    }
}
