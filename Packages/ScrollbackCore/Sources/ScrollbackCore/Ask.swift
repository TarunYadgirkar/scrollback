import Foundation
import FoundationModels

/// Plain-English questions answered by Apple's on-device model. The model
/// never sees raw data up front; it calls `activity` with the window it needs.
public struct Asker: Sendable {
    public struct Answer: Sendable {
        public let text: String
        /// Windows the model looked at, so the UI can jump the timeline there.
        public let windows: [DateInterval]
    }

    public enum Failure: Error, CustomStringConvertible {
        case modelUnavailable(String)

        public var description: String {
            switch self {
            case .modelUnavailable(let reason): "Apple Intelligence isn't available (\(reason)). Turn it on in System Settings to use Ask."
            }
        }
    }

    let store: SessionStore

    public init(store: SessionStore) {
        self.store = store
    }

    public static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func ask(_ question: String, now: Date = .now) async throws -> Answer {
        if case .unavailable(let reason) = SystemLanguageModel.default.availability {
            throw Failure.modelUnavailable(String(describing: reason))
        }
        let log = WindowLog()
        let session = LanguageModelSession(
            tools: [ActivityTool(store: store, log: log), LatestBingeTool(store: store, log: log, now: now)],
            instructions: Self.instructions(now: now)
        )
        let response = try await session.respond(to: question)
        return Answer(text: response.content, windows: await log.windows)
    }

    static func instructions(now: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let weekday = now.formatted(.dateTime.weekday(.wide))
        return """
            You answer questions about the user's own phone and computer usage.
            Right now it is \(weekday) \(Format.machineTime(now)). Today is \(Format.machineTime(today).prefix(10)); yesterday was \(Format.machineTime(yesterday).prefix(10)).
            Always call a tool before answering. For questions about a time period, call activity with the narrowest window that covers it. \
            For "last night" use yesterday 18:00 to today 06:00. For the most recent doomscroll, last scroll, or when the user stopped scrolling, call latest_binge.
            A doomscroll means only what the tool output lists under binges. If it says none, tell the user there were none. Never call work or messaging apps a doomscroll.
            Answer in two or three short sentences. Lead with the direct answer: the main apps and how long. \
            Copy times and durations exactly as the tool output writes them. Never convert or calculate times yourself.
            """
    }
}

actor WindowLog {
    private(set) var windows: [DateInterval] = []
    func record(_ w: DateInterval) { windows.append(w) }
}

struct ActivityTool: Tool {
    let name = "activity"
    let description = "Returns what the user did on iPhone and Mac between two local times: total time per app, doomscroll binges, and a log of sessions."

    let store: SessionStore
    let log: WindowLog

    @Generable
    struct Arguments {
        @Guide(description: "Start of the window in local time, formatted yyyy-MM-dd HH:mm")
        var from: String
        @Guide(description: "End of the window in local time, formatted yyyy-MM-dd HH:mm")
        var to: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let start = Format.parseMachineTime(arguments.from),
              let end = Format.parseMachineTime(arguments.to)
        else { return "Could not read those times. Use the format yyyy-MM-dd HH:mm." }
        guard end > start else { return "The end time must be after the start time." }
        let window = DateInterval(start: start, end: end)
        await log.record(window)
        let sessions = try await store.sessions(overlapping: window)
        return ActivityReport(window: window, sessions: sessions).promptText()
    }
}

struct LatestBingeTool: Tool {
    static let lookback: TimeInterval = 14 * 86_400

    let name = "latest_binge"
    let description = "Finds the user's most recent doomscroll binge: when it started and ended, how long it lasted, and which apps."

    let store: SessionStore
    let log: WindowLog
    let now: Date

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let window = DateInterval(start: now.addingTimeInterval(-Self.lookback), end: now)
        let sessions = try await store.sessions(overlapping: window)
        guard let binge = BingeDetector.binges(in: sessions).last else { return "No doomscroll binges in the last 14 days." }
        await log.record(DateInterval(start: binge.start, end: binge.end))
        let hops = binge.hops.map(AppCatalog.name(for:)).joined(separator: " > ")
        let ago = Format.duration(now.timeIntervalSince(binge.end))
        return """
            Most recent binge on \(binge.device.rawValue): \(Format.spokenTime(binge.start)) to \(Format.spokenTime(binge.end)), \
            lasted \(Format.duration(binge.span)) (\(Format.duration(binge.activeTime)) actively in social apps), ended \(ago) ago. Apps in order: \(hops).
            """
    }
}
