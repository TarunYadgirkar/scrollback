import SwiftUI
import ScrollbackCore

struct RibbonView: View {
    let report: ActivityReport
    let focusWindow: DateInterval?
    @Binding var selection: Selection?
    @Binding var hoverDate: Date?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let layout = RibbonLayout(window: report.window, width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawHours(layout, in: &context)
                    drawFocus(layout, in: &context)
                    drawSessions(layout, in: &context)
                    drawBinges(layout, in: &context)
                    drawNow(layout, in: &context)
                    drawCursor(layout, in: &context)
                }
                .frame(height: layout.height)
                .contentShape(Rectangle())
                .onTapGesture { point in select(at: point, layout: layout) }
                #if os(macOS)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hoverDate = layout.date(atY: point.y)
                    case .ended: hoverDate = nil
                    }
                }
                #endif
            }
        }
        .frame(height: RibbonLayout(window: report.window, width: 0).height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func select(at point: CGPoint, layout: RibbonLayout) {
        if let binge = layout.binge(at: point, in: report.binges) {
            selection = selection == .binge(binge) ? nil : .binge(binge)
        } else if let session = layout.session(at: point, in: report.sessions) {
            selection = selection == .session(session) ? nil : .session(session)
        } else {
            selection = nil
        }
    }

    // MARK: Drawing

    private func drawHours(_ layout: RibbonLayout, in context: inout GraphicsContext) {
        for (index, hour) in layout.hours.enumerated() {
            let y = layout.y(hour)
            var line = Path()
            line.move(to: CGPoint(x: RibbonLayout.gutter - Space.xs, y: y))
            line.addLine(to: CGPoint(x: layout.width, y: y))
            let isMajor = index % 6 == 0
            context.stroke(line, with: .color(isMajor ? Palette.inkFaint.opacity(0.6) : Palette.rule), lineWidth: isMajor ? 1 : 0.5)
            let label = Text(hour.hourLabel).font(TypeScale.monoSmall).foregroundStyle(isMajor ? Palette.inkMuted : Palette.inkFaint)
            context.draw(label, at: CGPoint(x: RibbonLayout.gutter - Space.s, y: y + Space.xxs), anchor: .topTrailing)
        }
        for device in DeviceKind.allCases {
            let lane = CGRect(x: layout.laneX(device), y: 0, width: layout.laneWidth, height: layout.height)
            context.fill(Path(lane), with: .color(Palette.ink.opacity(colorScheme == .dark ? 0.03 : 0.025)))
        }
    }

    private func drawFocus(_ layout: RibbonLayout, in context: inout GraphicsContext) {
        guard let focus = focusWindow?.intersection(with: report.window) else { return }
        let band = CGRect(x: RibbonLayout.gutter, y: layout.y(focus.start), width: layout.laneWidth * 2 + RibbonLayout.laneGap, height: max(2, layout.y(focus.end) - layout.y(focus.start)))
        context.fill(Path(band), with: .color(Palette.ink.opacity(0.07)))
        for edge in [band.minY, band.maxY] {
            var line = Path()
            line.move(to: CGPoint(x: band.minX, y: edge))
            line.addLine(to: CGPoint(x: band.maxX, y: edge))
            context.stroke(line, with: .color(Palette.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func drawSessions(_ layout: RibbonLayout, in context: inout GraphicsContext) {
        for session in report.sessions {
            let rect = layout.rect(for: session).insetBy(dx: 0, dy: rectInset(for: session, layout: layout))
            let category = AppCatalog.category(for: session.bundleID)
            let isSelected = selection == .session(session)
            let color = Palette.category(category)
            let path = rect.height > 4 ? Path(roundedRect: rect, cornerRadius: Radius.block) : Path(rect)
            context.fill(path, with: .color(color.opacity(isSelected ? 1 : category == .other ? 0.9 : 0.85)))
            if isSelected {
                context.stroke(path, with: .color(Palette.ink), lineWidth: 1.5)
            }
            guard rect.height >= RibbonLayout.labelMinHeight else { continue }
            let name = Text(AppCatalog.name(for: session.bundleID))
                .font(TypeScale.label)
                .foregroundStyle(category == .other ? Palette.ink : .white)
            var clipped = context
            clipped.clip(to: Path(rect))
            clipped.draw(name, at: CGPoint(x: rect.minX + Space.s, y: rect.minY + Space.xs), anchor: .topLeading)
        }
    }

    /// Back-to-back sessions get a hairline gap so app switches stay visible.
    private func rectInset(for session: Session, layout: RibbonLayout) -> CGFloat {
        layout.rect(for: session).height > 3 ? 0.5 : 0
    }

    private func drawBinges(_ layout: RibbonLayout, in context: inout GraphicsContext) {
        var labelFloor: CGFloat = -.infinity
        for binge in report.binges {
            let top = layout.y(binge.start), bottom = layout.y(binge.end)
            let x = layout.bracketX
            let isSelected = selection == .binge(binge)
            var bracket = Path()
            bracket.move(to: CGPoint(x: x + RibbonLayout.bracketCap, y: top))
            bracket.addLine(to: CGPoint(x: x, y: top))
            bracket.addLine(to: CGPoint(x: x, y: bottom))
            bracket.addLine(to: CGPoint(x: x + RibbonLayout.bracketCap, y: bottom))
            context.stroke(bracket, with: .color(Palette.signal), style: StrokeStyle(lineWidth: isSelected ? 3 : 2, lineCap: .round, lineJoin: .round))

            let labelTop = max(top - 2, labelFloor)
            let labelX = x + RibbonLayout.bracketCap + Space.xs
            context.draw(Text(Format.duration(binge.span)).font(TypeScale.readoutSmall).foregroundStyle(Palette.signal), at: CGPoint(x: labelX, y: labelTop), anchor: .topLeading)
            let distinct = binge.hops.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let hops = distinct.prefix(2).map(AppCatalog.name(for:)).joined(separator: " + ") + (distinct.count > 2 ? " +\(distinct.count - 2)" : "")
            var clipped = context
            clipped.clip(to: Path(CGRect(x: labelX, y: labelTop, width: layout.width - labelX, height: RibbonLayout.bracketLabelHeight)))
            clipped.draw(Text(hops).font(TypeScale.label).foregroundStyle(Palette.ink), at: CGPoint(x: labelX, y: labelTop + 22), anchor: .topLeading)
            context.draw(Text(binge.start.shortClock).font(TypeScale.monoSmall).foregroundStyle(Palette.inkMuted), at: CGPoint(x: labelX, y: labelTop + 36), anchor: .topLeading)
            labelFloor = labelTop + RibbonLayout.bracketLabelHeight + Space.s
        }
    }

    private func drawNow(_ layout: RibbonLayout, in context: inout GraphicsContext) {
        let now = Date.now
        guard report.window.contains(now) else { return }
        let y = layout.y(now)
        var line = Path()
        line.move(to: CGPoint(x: RibbonLayout.gutter, y: y))
        line.addLine(to: CGPoint(x: layout.width, y: y))
        context.stroke(line, with: .color(Palette.ink), lineWidth: 1)
        context.fill(Path(ellipseIn: CGRect(x: RibbonLayout.gutter - 3, y: y - 3, width: 6, height: 6)), with: .color(Palette.ink))
    }

    private func drawCursor(_ layout: RibbonLayout, in context: inout GraphicsContext) {
        guard let hoverDate, report.window.contains(hoverDate) else { return }
        let y = layout.y(hoverDate)
        var line = Path()
        line.move(to: CGPoint(x: RibbonLayout.gutter, y: y))
        line.addLine(to: CGPoint(x: layout.bracketX - RibbonLayout.bracketInset, y: y))
        context.stroke(line, with: .color(Palette.ink.opacity(0.55)), lineWidth: 0.5)
        let tag = Text(hoverDate.shortClock).font(TypeScale.monoSmall.weight(.semibold)).foregroundStyle(Palette.raised)
        let resolved = context.resolve(tag)
        let size = resolved.measure(in: CGSize(width: 100, height: 20))
        let pill = CGRect(x: RibbonLayout.gutter - size.width - Space.s - Space.xs, y: y - size.height / 2 - 2, width: size.width + Space.s, height: size.height + 4)
        context.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(Palette.ink))
        context.draw(resolved, at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center)
    }

    private var accessibilitySummary: String {
        let parts = DeviceKind.allCases.map { "\($0.label) \(Format.duration(report.total(on: $0)))" }
        let binges = report.binges.map { "binge \(Format.duration($0.span)) at \($0.start.shortClock)" }
        return (parts + binges).joined(separator: ", ")
    }
}
