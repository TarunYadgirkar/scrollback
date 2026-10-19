import SwiftUI
import ScrollbackCore

/// The day by app: each app's total active time, most used first. Tap one to see when it was open.
struct AppTotalsList<Header: View>: View {
    let model: AppModel
    @ViewBuilder let header: Header
    @State private var expanded: Set<String> = []

    private var apps: [ActivityReport.AppTotal] { model.report.apps(on: model.device) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.s) {
                header.padding(.bottom, Space.s)
                if apps.isEmpty {
                    empty
                } else {
                    SectionLabel(text: "\(apps.count) apps", detail: Format.duration(model.report.total(on: model.device)))
                }
                let longest = apps.first?.time ?? 1
                ForEach(apps) { app in
                    AppTotalRow(
                        app: app,
                        share: app.time / max(longest, 1),
                        sessions: sessions(of: app),
                        isExpanded: expanded.contains(app.id)
                    ) { toggle(app) }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
        }
        .refreshable { await model.refresh() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Nothing recorded").font(TypeScale.bodyStrong).foregroundStyle(Palette.ink)
            Text("No app use longer than a few seconds on this day.").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
        }
        .padding(.vertical, Space.xl)
    }

    private func sessions(of app: ActivityReport.AppTotal) -> [Session] {
        model.report.sessions.filter { $0.device == app.device && $0.bundleID == app.bundleID }.reversed()
    }

    private func toggle(_ app: ActivityReport.AppTotal) {
        withAnimation(Motion.quick) {
            if expanded.contains(app.id) { expanded.remove(app.id) } else { expanded.insert(app.id) }
        }
    }
}

private struct AppTotalRow: View {
    let app: ActivityReport.AppTotal
    /// This app's time against the day's most used app, for the bar.
    let share: Double
    let sessions: [Session]
    let isExpanded: Bool
    let onToggle: () -> Void

    private var category: AppCategory { AppCatalog.category(for: app.bundleID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) { summary }
                .buttonStyle(PressScale())
                .accessibilityHint(isExpanded ? "Hides each time it was open" : "Shows each time it was open")
            if isExpanded { detail }
        }
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                AppIconView(bundleID: app.bundleID, size: 28)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(app.name).font(TypeScale.bodyStrong).foregroundStyle(Palette.ink).lineLimit(1)
                    Text("\(category.label) · opened \(app.opens)×")
                        .font(TypeScale.label)
                        .foregroundStyle(Palette.inkMuted)
                }
                Spacer(minLength: Space.s)
                Text(Format.duration(app.time))
                    .font(TypeScale.readoutSmall)
                    .foregroundStyle(category == .social ? Palette.signal : Palette.ink)
                Image(systemName: "chevron.down")
                    .font(TypeScale.label)
                    .foregroundStyle(Palette.inkFaint)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            GeometryReader { proxy in
                Capsule().fill(Palette.category(category))
                    .frame(width: max(2, proxy.size.width * share))
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .padding(Space.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: Space.xs + Space.xxs) {
            Rectangle().fill(Palette.rule).frame(height: 1).padding(.bottom, Space.xs)
            ForEach(sessions) { session in
                HStack(spacing: Space.s) {
                    Text("\(session.start.shortClock) – \(session.end.shortClock)")
                        .font(TypeScale.monoSmall)
                        .foregroundStyle(Palette.inkMuted)
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
        .transition(.opacity)
    }
}
