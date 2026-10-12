import SwiftUI
import ScrollbackCore

/// Lane headers plus a live readout: what's under the cursor or what's selected.
struct ReadoutBar: View {
    let report: ActivityReport
    let selection: Selection?
    let hoverDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            laneHeaders
            detail
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .padding(.leading, RibbonLayout.gutter)
        }
        .padding(.vertical, Space.s)
        .background(Palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
    }

    private var laneHeaders: some View {
        GeometryReader { proxy in
            let layout = RibbonLayout(window: report.window, width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(DeviceKind.allCases, id: \.self) { device in
                    HStack(spacing: Space.xs) {
                        Text(device.label).font(TypeScale.label).foregroundStyle(Palette.inkMuted)
                        Text(Format.duration(report.total(on: device))).font(TypeScale.mono).foregroundStyle(Palette.ink)
                    }
                    .frame(width: layout.laneWidth, alignment: .leading)
                    .offset(x: layout.laneX(device))
                }
                Text("Binges").font(TypeScale.label).foregroundStyle(Palette.signal)
                    .offset(x: layout.bracketX - RibbonLayout.bracketInset)
            }
        }
        .frame(height: 18)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .session(let s): SessionReadout(session: s)
        case .binge(let b): BingeReadout(binge: b)
        case nil: hoverReadout
        }
    }

    @ViewBuilder private var hoverReadout: some View {
        if let hoverDate, let s = report.sessions.first(where: { $0.interval.contains(hoverDate) }) {
            SessionReadout(session: s)
        } else if hoverDate != nil {
            Text("Nothing open").font(TypeScale.label).foregroundStyle(Palette.inkFaint)
        } else {
            Text(hint).font(TypeScale.label).foregroundStyle(Palette.inkFaint)
        }
    }

    private var hint: String {
        #if os(macOS)
        "Point at the timeline to read any moment. Click a block or bracket to pin it."
        #else
        "Tap a block or bracket for details."
        #endif
    }
}

struct SessionReadout: View {
    let session: Session

    var body: some View {
        HStack(spacing: Space.s) {
            Circle().fill(Palette.category(AppCatalog.category(for: session.bundleID))).frame(width: 8, height: 8)
            Text(AppCatalog.name(for: session.bundleID)).font(TypeScale.bodyStrong).foregroundStyle(Palette.ink)
            Text("\(session.start.preciseClock) – \(session.end.preciseClock)").font(TypeScale.mono).foregroundStyle(Palette.inkMuted)
            Text(Format.preciseDuration(session.duration)).font(TypeScale.mono.weight(.semibold)).foregroundStyle(Palette.ink)
            if let reason = session.reason {
                Text("from \(reason.label)").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
            }
        }
        .lineLimit(1)
    }
}

struct BingeReadout: View {
    let binge: Binge

    var body: some View {
        HStack(spacing: Space.s) {
            Text(Format.duration(binge.span)).font(TypeScale.bodyStrong).foregroundStyle(Palette.signal)
            Text("\(binge.start.shortClock) – \(binge.end.shortClock)").font(TypeScale.mono).foregroundStyle(Palette.inkMuted)
            Text(binge.hops.map(AppCatalog.name(for:)).joined(separator: " → ")).font(TypeScale.label).foregroundStyle(Palette.ink)
            Text("\(Format.duration(binge.activeTime)) in apps").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
        }
        .lineLimit(1)
    }
}
