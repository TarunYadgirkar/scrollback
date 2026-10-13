import AppIntents
import ScrollbackCore

/// Apps worth logging live. Messages and Mail are left out: they're opened hundreds of times a day
/// and would fire an automation every time.
enum TrackedApp: String, AppEnum {
    case instagram = "com.burbn.instagram"
    case youtube = "com.google.ios.youtube"
    case x = "com.atebits.Tweetie2"
    case linkedin = "com.linkedin.LinkedIn"
    case yikyak = "com.yikyak.2"
    case snapchat = "com.toyopagroup.picaboo"
    case reddit = "com.reddit.Reddit"
    case tiktok = "com.zhiliaoapp.musically"
    case threads = "com.burbn.barcelona"
    case safari = "com.apple.mobilesafari"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    static let caseDisplayRepresentations: [TrackedApp: DisplayRepresentation] = [
        .instagram: "Instagram", .youtube: "YouTube", .x: "X", .linkedin: "LinkedIn", .yikyak: "Yik Yak",
        .snapchat: "Snapchat", .reddit: "Reddit", .tiktok: "TikTok", .threads: "Threads", .safari: "Safari",
    ]
}

enum AppEventKind: String, AppEnum {
    case opened, closed

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Event"
    static let caseDisplayRepresentations: [AppEventKind: DisplayRepresentation] = [.opened: "opened", .closed: "closed"]
}

struct LogAppEvent: AppIntent {
    static let title: LocalizedStringResource = "Log App Event"
    static let description = IntentDescription("Records that an app was opened or closed, so Scrollback shows it right away instead of waiting for Apple's sync.")
    static let openAppWhenRun = false

    @Parameter(title: "App") var app: TrackedApp
    @Parameter(title: "Event") var event: AppEventKind

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$app) \(\.$event)")
    }

    func perform() async throws -> some IntentResult {
        let store = try SessionStore(url: SessionStore.defaultURL())
        try await store.appendLiveEvent(FocusEvent(bundleID: app.rawValue, date: .now, isStart: event == .opened, reason: nil))
        return .result()
    }
}
