import SwiftUI
import ScrollbackCore

/// Lane headers plus a readout of what's selected (or, on the Mac, under the pointer).
struct ReadoutBar: View {
    let report: ActivityReport
    let devices: [DeviceKind]
    let selection: Selection?
    let hoverDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            laneHeaders
            if let detail = detailView {
                detail
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, RibbonLayout.gutter)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, Space.s)
        .background(Palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
        .animation(Motion.quick, value: selection)
    }

    private var laneHeaders: some View {
        GeometryReader { proxy in
            let layout = RibbonLayout(window: report.window, width: proxy.size.width, devices: devices)
            ZStack(alignment: .topLeading) {
                ForEach(devices, id: \.self) { device in
                    HStack(spacing: Space.xs) {
                        Text(device.label).font(TypeScale.label).foregroundStyle(Palette.inkMuted)
                        Text(Format.duration(report.total(on: device))).font(TypeScale.mono).foregroundStyle(Palette.ink)
                    }
                    .frame(width: layout.laneWidth, alignment: .leading)
                    .offset(x: layout.laneX(device) ?? 0)
                }
                Text("Binges").font(TypeScale.label).foregroundStyle(Palette.signal)
                    .offset(x: layout.bracketX - RibbonLayout.bracketInset)
            }
        }
        .frame(height: 18)
    }

    private var detailView: AnyView? {
        switch selection {
        case .session(let s): return AnyView(SessionReadout(session: s))
        case .binge(let b): return AnyView(BingeReadout(binge: b))
        case nil:
            guard let hoverDate else { return nil }
            if let s = report.sessions.first(where: { devices.contains($0.device) && $0.interval.contains(hoverDate) }) {
                return AnyView(SessionReadout(session: s))
            }
            return AnyView(Text("Nothing open").font(TypeScale.label).foregroundStyle(Palette.inkFaint))
        }
    }
}

struct SessionReadout: View {
    let session: Session

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s) { parts }
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.s) { name; duration }
                HStack(spacing: Space.s) { times; reason }
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder private var parts: some View { name; times; duration; reason }

    private var name: some View {
        HStack(spacing: Space.s) {
            AppIconView(bundleID: session.bundleID, size: 18)
            Text(AppCatalog.name(for: session.bundleID)).font(TypeScale.bodyStrong).foregroundStyle(Palette.ink)
        }
    }

    private var times: some View {
        Text("\(session.start.preciseClock) – \(session.end.preciseClock)").font(TypeScale.mono).foregroundStyle(Palette.inkMuted)
    }

    private var duration: some View {
        Text(Format.preciseDuration(session.duration)).font(TypeScale.mono.weight(.semibold)).foregroundStyle(Palette.ink)
    }

    @ViewBuilder private var reason: some View {
        if let reason = session.reason {
            Text("opened from \(reason.label)").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
        }
    }
}

struct BingeReadout: View {
    let binge: Binge

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.s) {
                Text(Format.duration(binge.span)).font(TypeScale.bodyStrong).foregroundStyle(Palette.signal)
                Text("\(binge.start.shortClock) – \(binge.end.shortClock)").font(TypeScale.mono).foregroundStyle(Palette.inkMuted)
                Text("\(Format.duration(binge.activeTime)) in apps").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
            }
            Text(binge.hops.map(AppCatalog.name(for:)).joined(separator: " → ")).font(TypeScale.label).foregroundStyle(Palette.ink)
        }
        .lineLimit(1)
    }
}
