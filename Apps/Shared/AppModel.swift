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
    /// The last refresh's setup problem. Unlike `status`, it holds through the next refresh's
    /// `.syncing`, so setup screens don't flicker every time the app checks again.
    private(set) var setupNeed: SetupNeed?
    private(set) var askState: AskState = .idle
    private(set) var earliestDay: Date?
    /// Newest data each device has delivered. iPhone data arrives via Apple's sync, often hours late.
    private(set) var dataThrough: [DeviceKind: Date] = [:]
    /// Doomscroll time from the Screen Time monitor, newer than Apple's record.
    private(set) var live: [Session] = []
    var question = ""
    /// Set by a menu command or shortcut until the Ask field has taken focus, which may first need
    /// the list to scroll it back into existence.
    private(set) var wantsAskFocus = false
    /// Bumped on every jump to a window, so asking for the same one twice still scrolls back to it.
    private(set) var focusRequest = 0
    /// True while the user is on today, so a long-running app rolls over to the new day at midnight.
    private var followsToday = true
    var selection: Selection?
    var focusWindow: DateInterval?
    var viewMode: ViewMode = Preference.viewMode {
        didSet { Preference.viewMode = viewMode }
    }
    var device: DeviceKind = Preference.device {
        didSet {
            Preference.device = device
            selection = nil
            focusWindow = nil
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
        guard isToday, device == .iphone else { return nil }
        return iPhoneStaleSince
    }

    /// Where today's iPhone record stops, when that's more than a little while ago, whatever day is on screen.
    var iPhoneStaleSince: Date? {
        guard let through = dataThrough[.iphone], Date.now.timeIntervalSince(through) > Self.staleAfter else { return nil }
        return through
    }

    /// Apple's iPhone record normally reaches the Mac 10 to 17 hours late. Past a day, the Mac
    /// itself has stopped reading (quit, or lost Full Disk Access) rather than Apple running behind.
    static let macStoppedAfter: TimeInterval = 24 * 60 * 60

    var macStoppedSending: Bool {
        guard let through = dataThrough[.iphone] else { return false }
        return Date.now.timeIntervalSince(through) > Self.macStoppedAfter
    }

    func refresh() async {
        guard status != .syncing else { return }
        status = .syncing
        let next: SyncStatus
        let need: SetupNeed?
        do {
            let result = try await provider.refresh(into: store)
            next = .synced(.now, note: result.warnings.first)
            need = nil
        } catch {
            need = provider.setupNeed(for: error)
            next = need.map(SyncStatus.needsSetup) ?? .failed(Self.explain(error))
        }
        // Reload first, so screens gated on "syncing with no data yet" don't flash an empty day in between.
        await reload()
        setupNeed = need
        status = next
    }

    /// A sentence for the user, not a Swift dump of the error.
    static func explain(_ error: any Error) -> String {
        if let message = (error as? LocalizedError)?.errorDescription { return message }
        // Swift errors in Core describe themselves; Cocoa errors are better read through localizedDescription.
        if !(type(of: error) is NSError.Type) { return String(describing: error) }
        return (error as NSError).localizedDescription
    }

    func reload() async {
        let todayStart = Calendar.current.startOfDay(for: .now)
        if followsToday, day != todayStart {
            day = todayStart
            selection = nil
            focusWindow = nil
        }
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
        followsToday = start == Calendar.current.startOfDay(for: .now)
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
            askState = .failed(Self.explain(error))
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

    func requestAskFocus() {
        guard Asker.availability != .unsupported else { return }
        wantsAskFocus = true
    }

    func askFocusTaken() {
        wantsAskFocus = false
    }

    /// Lets go of whatever the day is pinned to: a selection, a jump, an answer.
    func clearFocus() {
        selection = nil
        focusWindow = nil
        switch askState {
        case .answered, .failed: dismissAnswer()
        case .idle, .thinking: break
        }
    }

    func focus(on window: DateInterval) async {
        let target = Calendar.current.startOfDay(for: window.start)
        if target != day { await show(day: target) }
        // Ask answers about either device; show the one that was actually in use then.
        let current = activeTime(on: device, in: window)
        if current < 60, let busier = DeviceKind.allCases.first(where: { activeTime(on: $0, in: window) >= 60 }) {
            device = busier
        }
        focusWindow = window
        focusRequest += 1
    }

    private func activeTime(on device: DeviceKind, in window: DateInterval) -> TimeInterval {
        report.sessions.filter { $0.device == device }.reduce(0) { total, session in
            total + (session.interval.intersection(with: window)?.duration ?? 0)
        }
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
