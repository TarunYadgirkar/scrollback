import SwiftUI
import ScrollbackCore

/// The day as readable rows: each continuous period of use, newest first.
struct StretchList<Header: View>: View {
    let model: AppModel
    /// Scrolls away with the rows, so the list gets the whole screen once you start reading.
    @ViewBuilder let header: Header
    @State private var expanded: Set<String> = []

    private var stretches: [Stretch] {
        model.report.stretches(on: model.device).sorted { $0.start > $1.start }
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s) {
                    header.padding(.bottom, Space.s)
                    if stretches.isEmpty { empty }
                    ForEach(stretches) { stretch in
                        StretchRow(
                            stretch: stretch,
                            binge: model.report.binge(overlapping: stretch),
                            isExpanded: expanded.contains(stretch.id),
                            isFocused: isFocused(stretch)
                        ) { toggle(stretch) }
                        .id(stretch.id)
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
            }
            .refreshable { await model.refresh() }
            .onChange(of: model.focusWindow) { _, _ in
                guard let target = stretches.last(where: isFocused) else { return }
                expanded.insert(target.id)
                withAnimation(.easeOut(duration: 0.3)) { reader.scrollTo(target.id, anchor: .top) }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Nothing recorded").font(TypeScale.bodyStrong).foregroundStyle(Palette.ink)
            Text(emptyDetail).font(TypeScale.label).foregroundStyle(Palette.inkMuted)
        }
        .padding(.vertical, Space.xl)
    }

    private var emptyDetail: String {
        guard model.device == .iphone, model.isToday else {
            return "No app use longer than a few seconds on this day."
        }
        return "Your iPhone's activity reaches your Mac through Apple's sync, which can run a few hours behind."
    }

    private func isFocused(_ stretch: Stretch) -> Bool {
        guard let focus = model.focusWindow else { return false }
        return stretch.start < focus.end && focus.start < stretch.end
    }

    private func toggle(_ stretch: Stretch) {
        withAnimation(Motion.quick) {
            if expanded.contains(stretch.id) { expanded.remove(stretch.id) } else { expanded.insert(stretch.id) }
        }
    }
}

private struct StretchRow: View {
    static let topApps = 3

    let stretch: Stretch
    let binge: Binge?
    let isExpanded: Bool
    let isFocused: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) { summary }
                .buttonStyle(PressScale())
                .accessibilityHint(isExpanded ? "Hides each app" : "Shows each app")
            if isExpanded { detail }
        }
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(alignment: .leading) {
            if binge != nil {
                UnevenRoundedRectangle(topLeadingRadius: Radius.card, bottomLeadingRadius: Radius.card)
                    .fill(Palette.signal)
                    .frame(width: 4)
            }
        }
        .shadow(color: .black.opacity(isFocused ? 0.14 : 0.05), radius: isFocused ? 8 : 2, y: 1)
        .scaleEffect(isFocused ? 1.01 : 1)
        .animation(Motion.quick, value: isFocused)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(stretch.start.shortClock) – \(stretch.end.shortClock)")
                    .font(TypeScale.mono)
                    .foregroundStyle(Palette.inkMuted)
                Spacer()
                if let binge {
                    Text("Binge \(Format.duration(binge.span))")
                        .font(TypeScale.label.weight(.semibold))
                        .foregroundStyle(Palette.signal)
                }
                Image(systemName: "chevron.down")
                    .font(TypeScale.label)
                    .foregroundStyle(Palette.inkFaint)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(Format.duration(stretch.activeTime))
                    .font(TypeScale.readoutSmall)
                    .foregroundStyle(stretch.socialTime > stretch.activeTime / 2 ? Palette.signal : Palette.ink)
                Text(appsLine)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            ShareBar(apps: stretch.apps, total: stretch.activeTime)
        }
        .padding(Space.m)
        .padding(.leading, binge == nil ? 0 : Space.xs)
        .contentShape(Rectangle())
    }

    private var appsLine: String {
        let names = stretch.apps.prefix(Self.topApps).map(\.name)
        let more = stretch.apps.count - Self.topApps
        return names.joined(separator: ", ") + (more > 0 ? " +\(more)" : "")
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: Space.xs + Space.xxs) {
            Rectangle().fill(Palette.rule).frame(height: 1).padding(.bottom, Space.xs)
            ForEach(stretch.sessions) { session in
                HStack(spacing: Space.s) {
                    Text(session.start.shortClock)
                        .font(TypeScale.monoSmall)
                        .foregroundStyle(Palette.inkMuted)
                        .frame(width: 56, alignment: .leading)
                    Circle().fill(Palette.category(AppCatalog.category(for: session.bundleID))).frame(width: 7, height: 7)
                    Text(AppCatalog.name(for: session.bundleID)).font(TypeScale.label).foregroundStyle(Palette.ink)
                    if let reason = session.reason {
                        Text(reason.label).font(TypeScale.label).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer()
                    Text(Format.preciseDuration(session.duration)).font(TypeScale.monoSmall).foregroundStyle(Palette.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding([.horizontal, .bottom], Space.m)
        .padding(.leading, binge == nil ? 0 : Space.xs)
        .transition(.opacity)
    }
}

/// One thin bar split by app, colored by category.
private struct ShareBar: View {
    let apps: [Stretch.AppShare]
    let total: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(apps) { app in
                    Rectangle()
                        .fill(Palette.category(app.category))
                        .frame(width: max(1, (proxy.size.width - CGFloat(apps.count - 1)) * app.time / max(total, 1)))
                }
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
