import SwiftUI
import ScrollbackCore

struct DayScreen: View {
    @Bindable var model: AppModel
    @Environment(\.screenTimeToday) private var screenTimeToday
    /// Bumped after a pull-to-refresh so Screen Time's report is rebuilt and reads fresh numbers.
    @State private var reportGeneration = 0

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
            if model.device == .iphone, model.isToday, let screenTimeToday {
                liveToday(screenTimeToday)
            } else {
                StretchList(model: model) { top }
            }
        case .timeline:
            VStack(alignment: .leading, spacing: 0) {
                top
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
                TimelinePane(model: model)
            }
        }
    }

    /// Today on the phone: Screen Time's own report under a fixed header. Touches on the report go to
    /// Screen Time rather than this app, so the page can't scroll from there; the report scrolls itself.
    /// The page is exactly one screen tall, so it only moves when pulled down from the header to refresh.
    private func liveToday(_ report: AnyView) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                DeviceSwitcher(model: model)
                DayHeader(model: model)
                AskBar(model: model)
                ActivityHeader(model: model)
                report.id(reportGeneration)
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .containerRelativeFrame(.vertical, alignment: .top)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .refreshable {
            await model.refresh()
            reportGeneration += 1
        }
        .animation(Motion.quick, value: model.askState)
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            DeviceSwitcher(model: model)
            DayHeader(model: model)
            if !isCompactTimeline {
                AskBar(model: model)
                RecapStrip(report: model.report, device: model.device)
                if let lag = model.iPhoneLag { FreshnessNote(through: lag, isLive: model.isTrackingLive) }
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

    /// The timeline's header stays fixed above the ribbon, and a phone screen can't fit Ask and the
    /// recap there too, so it keeps only the tabs, the day and the view toggle. Ask stays on the list.
    private var isCompactTimeline: Bool {
        #if os(iOS)
        model.viewMode == .timeline
        #else
        false
        #endif
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
    /// The phone's live Screen Time report for today, when access is granted. Nil on the Mac.
    @Entry var screenTimeToday: AnyView?
}
