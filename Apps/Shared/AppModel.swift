import SwiftUI
import ScrollbackCore

enum SetupNeed: Equatable {
    case fullDiskAccess
    case notPaired
}

enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced(Date, note: String?)
    case needsSetup(SetupNeed)
    case failed(String)
}

struct RefreshResult: Sendable {
    let added: Int
    let warnings: [String]
}

/// Where sessions come from: Biome on the Mac, the Mac itself on the iPhone.
protocol UsageProvider: Sendable {
    func refresh(into store: SessionStore) async throws -> RefreshResult
    func setupNeed(for error: any Error) -> SetupNeed?
}

enum Selection: Equatable {
    case session(Session)
    case binge(Binge)
}

enum AskState: Equatable {
    case idle
    case thinking
    case answered(String)
    case failed(String)
}

@MainActor @Observable
final class AppModel {
    let store: SessionStore
    private let provider: any UsageProvider

    private(set) var day: Date
    private(set) var report: ActivityReport
    /// Always today, for the menu bar, independent of the day being browsed.
    private(set) var today: ActivityReport
    private(set) var status: SyncStatus = .idle
    private(set) var askState: AskState = .idle
    private(set) var earliestDay: Date?
    /// Newest data each device has delivered. iPhone data arrives via Apple's sync, often hours late.
    private(set) var dataThrough: [DeviceKind: Date] = [:]
    /// Doomscroll time from the Screen Time monitor, newer than Apple's record.
    private(set) var live: [Session] = []
    var question = ""
    var selection: Selection?
    var focusWindow: DateInterval?
    var viewMode: ViewMode = Preference.viewMode {
        didSet { Preference.viewMode = viewMode }
    }
    var device: DeviceKind = Preference.device {
        didSet {
            Preference.device = device
            selection = nil
        }
    }

    init(store: SessionStore, provider: any UsageProvider) {
        self.store = store
        self.provider = provider
        let today = Calendar.current.startOfDay(for: .now)
        self.day = today
        let empty = ActivityReport(window: Self.window(for: today), sessions: [])
        self.report = empty
        self.today = empty
    }

    var isToday: Bool { Calendar.current.isDateInToday(day) }
    var canGoBack: Bool { earliestDay.map { day > $0 } ?? false }
    var hasData: Bool { earliestDay != nil }

    static let staleAfter: TimeInterval = 30 * 60

    /// When the iPhone's data stops short of now on today's view, the time it stops at.
    var isTrackingLive: Bool { !live.isEmpty }

    var iPhoneLag: Date? {
        guard isToday, device == .iphone, let through = dataThrough[.iphone],
              Date.now.timeIntervalSince(through) > Self.staleAfter
        else { return nil }
        return through
    }

    func refresh() async {
        guard status != .syncing else { return }
        status = .syncing
        do {
            let result = try await provider.refresh(into: store)
            status = .synced(.now, note: result.warnings.first)
        } catch {
            status = provider.setupNeed(for: error).map(SyncStatus.needsSetup) ?? .failed(String(describing: error))
        }
        await reload()
    }

    func reload() async {
        var through: [DeviceKind: Date] = [:]
        for device in DeviceKind.allCases {
            through[device] = try? await store.latestEnd(for: device)
        }
        dataThrough = through
        let cutoff = through[.iphone] ?? .distantPast
        live = await liveSessions(after: cutoff)

        let window = Self.window(for: day)
        report = ActivityReport(window: window, sessions: await sessions(in: window))
        let todayWindow = Self.window(for: Calendar.current.startOfDay(for: .now))
        today = window == todayWindow ? report : ActivityReport(window: todayWindow, sessions: await sessions(in: todayWindow))
        earliestDay = (try? await store.earliestStart()).map { Calendar.current.startOfDay(for: $0) }
    }

    /// Doomscroll milestones from the Screen Time monitor, past the point Apple's detailed record reaches.
    private func liveSessions(after cutoff: Date) async -> [Session] {
        let lookback = cutoff.addingTimeInterval(-86_400)
        let milestones = (try? await store.milestones(after: lookback)) ?? []
        return MilestoneTimeline.sessions(from: milestones).filter { $0.end > cutoff }
    }

    /// Apple's record, plus anything logged live on the phone after where that record stops.
    private func sessions(in window: DateInterval) async -> [Session] {
        let stored = (try? await store.sessions(overlapping: window)) ?? []
        return stored + live.filter { $0.start < window.end && $0.end > window.start }
    }

    func shift(days: Int) async {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        await show(day: next)
    }

    func show(day newDay: Date) async {
        let start = Calendar.current.startOfDay(for: newDay)
        guard start <= Calendar.current.startOfDay(for: .now) else { return }
        day = start
        selection = nil
        focusWindow = nil
        await reload()
    }

    func ask() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, askState != .thinking else { return }
        askState = .thinking
        do {
            let answer = try await Asker(store: store).ask(q)
            askState = .answered(answer.text)
            if let window = answer.windows.last { await focus(on: window) }
        } catch {
            askState = .failed(String(describing: error))
        }
    }

    func ask(_ suggestion: String) async {
        question = suggestion
        await ask()
    }

    func dismissAnswer() {
        askState = .idle
        question = ""
        focusWindow = nil
    }

    func focus(on window: DateInterval) async {
        let target = Calendar.current.startOfDay(for: window.start)
        if target != day { await show(day: target) }
        focusWindow = window
    }

    static func window(for day: Date) -> DateInterval {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        return DateInterval(start: day, end: end)
    }
}

/// View preferences. Both apps open on the iPhone, since that's where the scrolling happens.
private enum Preference {
    #if os(iOS)
    static let defaultMode = ViewMode.list
    #else
    static let defaultMode = ViewMode.timeline
    #endif

    static var viewMode: ViewMode {
        get { UserDefaults.standard.string(forKey: "viewMode").flatMap(ViewMode.init(rawValue:)) ?? defaultMode }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "viewMode") }
    }

    static var device: DeviceKind {
        get { UserDefaults.standard.string(forKey: "device").flatMap(DeviceKind.init(rawValue:)) ?? .iphone }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "device") }
    }
}
