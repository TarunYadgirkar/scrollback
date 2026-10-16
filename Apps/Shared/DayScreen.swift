import SwiftUI
import ScrollbackCore

struct DayScreen: View {
    @Bindable var model: AppModel
    @Environment(\.liveToday) private var liveToday
    @Environment(\.hourByHour) private var hourByHour

    var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            main
            Rectangle().fill(Palette.rule).frame(width: 1)
            Inspector(model: model).frame(width: 280)
        }
        .background(Palette.surface)
        #else
        main.background(Palette.surface)
        #endif
    }

    @ViewBuilder private var main: some View {
        switch model.viewMode {
        case .list:
            StretchList(model: model) { top }
        case .timeline:
            VStack(alignment: .leading, spacing: 0) {
                top
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
                TimelinePane(model: model)
            }
        }
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            DeviceSwitcher(model: model)
            DayHeader(model: model)
            AskBar(model: model)
            if model.device == .iphone, model.isToday, let liveToday {
                liveToday
            } else {
                RecapStrip(report: model.report, device: model.device)
                if let lag = model.iPhoneLag { FreshnessNote(through: lag, isLive: model.isTrackingLive) }
            }
            if model.device == .iphone, model.isToday, let hourByHour {
                Text("By hour").font(TypeScale.title).foregroundStyle(Palette.ink)
                hourByHour
            }
            ActivityHeader(model: model)
            if model.device == .iphone, model.isToday, model.isTrackingLive {
                Text("Doomscroll apps show up live in 5-minute steps. Everything else fills in from your Mac.")
                    .font(TypeScale.label)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(Motion.quick, value: model.askState)
    }
}

private struct TimelinePane: View {
    private static let leadIn: TimeInterval = 90 * 60

    @Bindable var model: AppModel
    @State private var hoverDate: Date?
    @State private var scrollPosition = ScrollPosition(edge: .top)

    private var devices: [DeviceKind] { [model.device] }

    var body: some View {
        VStack(spacing: 0) {
            ReadoutBar(report: model.report, devices: devices, selection: model.selection, hoverDate: hoverDate)
                .padding(.horizontal, Space.l)
            ScrollView {
                RibbonView(report: model.report, devices: devices, focusWindow: model.focusWindow, selection: $model.selection, hoverDate: $hoverDate)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
            }
            .scrollPosition($scrollPosition)
            .refreshable { await model.refresh() }
            .onChange(of: model.focusWindow) { _, window in scroll(to: window?.start) }
            .task(id: ScrollKey(day: model.report.window.start, count: model.report.sessions.count)) {
                scroll(to: model.focusWindow?.start ?? defaultScrollTarget, animated: false)
            }
        }
    }

    private struct ScrollKey: Hashable {
        let day: Date
        let count: Int
    }

    /// Open on the most recent activity rather than midnight.
    private var defaultScrollTarget: Date? {
        model.isToday ? Date.now.addingTimeInterval(-2 * 3600) : model.report.sessions.last?.start.addingTimeInterval(-3 * 3600)
    }

    private func scroll(to date: Date?, animated: Bool = true) {
        guard let date else { return }
        let y = max(0, RibbonLayout(window: model.report.window, width: 0).y(date.addingTimeInterval(-Self.leadIn)))
        if animated {
            withAnimation(.easeOut(duration: 0.3)) { scrollPosition.scrollTo(y: y) }
        } else {
            scrollPosition.scrollTo(y: y)
        }
    }
}

extension EnvironmentValues {
    /// The phone's live Screen Time card, when access is granted. Nil on the Mac.
    @Entry var liveToday: AnyView?
    /// Today's hours on the phone, newest first, from Screen Time.
    @Entry var hourByHour: AnyView?
}
