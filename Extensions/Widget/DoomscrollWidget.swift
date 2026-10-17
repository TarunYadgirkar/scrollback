import AppIntents
import ScrollbackCore
import SwiftUI
import WidgetKit

@main
struct ScrollbackWidgets: WidgetBundle {
    var body: some Widget {
        DoomscrollWidget()
    }
}

/// Today's doomscroll total on the Home Screen and Lock Screen, from the monitor's milestones.
/// It moves in the monitor's 5-minute steps (15 after 4 hours), so it trails Screen Time's own count a little.
struct DoomscrollWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SharedContainer.doomscrollWidgetKind, intent: DoomscrollWidgetIntent.self, provider: DoomscrollProvider()) { entry in
            DoomscrollWidgetView(entry: entry)
        }
        .configurationDisplayName("Doomscrolling today")
        .description("How long you've spent in your doomscroll apps today.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

/// Nothing to configure; an intent just lets the provider be async.
struct DoomscrollWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Doomscrolling today"
}

struct DoomscrollEntry: TimelineEntry, Sendable {
    let date: Date
    let today: DoomscrollToday
    /// False until doomscroll apps are picked in the app, so "0m" isn't shown for a day nobody is counting.
    let isTracking: Bool

    static let sample = DoomscrollEntry(date: .now, today: DoomscrollToday(minutes: 47, asOf: .now), isTracking: true)

    static func load(now: Date) async -> DoomscrollEntry {
        let calendar = Calendar.current
        // A second early, so a 0 written right at midnight is included.
        let since = calendar.startOfDay(for: now).addingTimeInterval(-1)
        var milestones: [Milestone] = []
        if let store = try? SessionStore(url: SessionStore.defaultURL()) {
            milestones = (try? await store.milestones(after: since)) ?? []
        }
        let today = DoomscrollToday.from(milestones, now: now, calendar: calendar)
        let isTracking = SharedContainer.defaults?.data(forKey: SharedContainer.monitoredSelectionKey) != nil
        return DoomscrollEntry(date: now, today: today, isTracking: isTracking || today.minutes > 0)
    }
}

struct DoomscrollProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DoomscrollEntry { .sample }

    func snapshot(for configuration: DoomscrollWidgetIntent, in context: Context) async -> DoomscrollEntry {
        context.isPreview ? .sample : await DoomscrollEntry.load(now: .now)
    }

    /// The monitor asks for a reload as steps land (at most every 15 minutes), so there's no polling. The second entry
    /// zeroes the count at midnight even if nothing wakes the widget then.
    func timeline(for configuration: DoomscrollWidgetIntent, in context: Context) async -> Timeline<DoomscrollEntry> {
        let now = Date.now
        let entry = await DoomscrollEntry.load(now: now)
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let reset = DoomscrollEntry(date: midnight, today: DoomscrollToday(minutes: 0, asOf: nil), isTracking: entry.isTracking)
        return Timeline(entries: [entry, reset], policy: .atEnd)
    }
}

struct DoomscrollWidgetView: View {
    let entry: DoomscrollEntry
    @Environment(\.widgetFamily) private var family

    private var total: String { Format.duration(TimeInterval(entry.today.minutes * 60)) }
    private var asOf: String { entry.today.asOf.map { "as of \(Format.clock($0))" } ?? "nothing yet" }

    var body: some View {
        content.containerBackground(for: .widget) {
            if family == .systemSmall { Palette.raised } else { Color.clear }
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Text(entry.isTracking ? "\(total) doomscrolling" : "Pick doomscroll apps")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(entry.isTracking ? total : "–")
                        .font(.system(size: 17, weight: .heavy).width(.expanded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .widgetAccentable()
                    Text("today").font(.system(size: 10, weight: .medium))
                }
                .padding(Space.xs)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text("Doomscrolling").font(.headline)
                if entry.isTracking {
                    Text(total)
                        .font(.system(size: 22, weight: .heavy).width(.expanded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .widgetAccentable()
                    Text(asOf).font(.caption)
                } else {
                    Text("Pick apps in Scrollback").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Doomscrolling today").font(TypeScale.label).foregroundStyle(Palette.inkMuted)
                Spacer(minLength: 0)
                if entry.isTracking {
                    Text(total)
                        .font(.system(size: 34, weight: .heavy).width(.expanded))
                        .foregroundStyle(Palette.signal)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(asOf).font(TypeScale.monoSmall).foregroundStyle(Palette.inkFaint)
                } else {
                    Text("Pick your doomscroll apps in Scrollback").font(TypeScale.bodyStrong).foregroundStyle(Palette.ink)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
