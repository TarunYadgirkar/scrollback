import SwiftUI
import ScrollbackCore

struct DayScreen: View {
    @Bindable var model: AppModel
    @State private var hoverDate: Date?
    @State private var scrollPosition = ScrollPosition(edge: .top)
    private static let leadIn: TimeInterval = 90 * 60

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

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.l) {
                DayHeader(model: model)
                AskBar(model: model)
                RecapStrip(report: model.report)
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.m)
            .animation(Motion.quick, value: model.askState)

            ReadoutBar(report: model.report, selection: model.selection, hoverDate: hoverDate)
                .padding(.horizontal, Space.l)

            ScrollView {
                RibbonView(report: model.report, focusWindow: model.focusWindow, selection: $model.selection, hoverDate: $hoverDate)
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
