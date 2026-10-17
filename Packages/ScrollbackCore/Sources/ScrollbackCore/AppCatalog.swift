import Foundation

public enum AppCategory: String, Sendable, Codable, CaseIterable {
    case social
    case messaging
    case work
    case other

    public var label: String {
        switch self {
        case .social: "Social"
        case .messaging: "Messaging"
        case .work: "Work"
        case .other: "Other"
        }
    }
}

public enum AppCatalog {
    struct Entry {
        let name: String
        let category: AppCategory
    }

    /// Foreground "apps" that are really lock screens, overlays, or system chrome.
    static let systemSurfaces: Set<String> = [
        "com.apple.SleepLockScreen", "com.apple.springboard", "com.apple.control-center",
        "com.apple.HeadphoneProxService", "com.apple.PassbookUIService", "com.apple.ScreenTimeUnlock",
        "com.apple.loginwindow", "com.apple.ScreenSaver.Engine", "com.apple.SecurityAgent",
        "com.apple.CoreAuthUI", "com.apple.UserNotificationCenter", "com.apple.dock",
        "com.apple.InCallService", "com.apple.siri", "com.apple.Spotlight",
    ]

    static let known: [String: Entry] = [
        "com.burbn.instagram": Entry(name: "Instagram", category: .social),
        "com.atebits.Tweetie2": Entry(name: "X", category: .social),
        "com.google.ios.youtube": Entry(name: "YouTube", category: .social),
        "com.zhiliaoapp.musically": Entry(name: "TikTok", category: .social),
        "com.reddit.Reddit": Entry(name: "Reddit", category: .social),
        "com.toyopagroup.picaboo": Entry(name: "Snapchat", category: .social),
        "com.yikyak.2": Entry(name: "Yik Yak", category: .social),
        "com.facebook.Facebook": Entry(name: "Facebook", category: .social),
        "com.burbn.barcelona": Entry(name: "Threads", category: .social),
        "AlexisBarreyat.BeReal": Entry(name: "BeReal", category: .social),
        "com.linkedin.LinkedIn": Entry(name: "LinkedIn", category: .social),
        "pinterest": Entry(name: "Pinterest", category: .social),
        "tv.twitch": Entry(name: "Twitch", category: .social),
        "com.apple.MobileSMS": Entry(name: "Messages", category: .messaging),
        "com.apple.iChat": Entry(name: "Messages", category: .messaging),
        "net.whatsapp.WhatsApp": Entry(name: "WhatsApp", category: .messaging),
        "net.whatsapp.WhatsApp.mac": Entry(name: "WhatsApp", category: .messaging),
        "com.hammerandchisel.discord": Entry(name: "Discord", category: .messaging),
        "com.facebook.Messenger": Entry(name: "Messenger", category: .messaging),
        "ph.telegra.Telegraph": Entry(name: "Telegram", category: .messaging),
        "com.tinyspeck.chatlyio": Entry(name: "Slack", category: .messaging),
        "com.tinyspeck.slackmacgap": Entry(name: "Slack", category: .messaging),
        "com.google.Gmail": Entry(name: "Gmail", category: .messaging),
        "com.apple.mobilemail": Entry(name: "Mail", category: .messaging),
        "com.apple.mail": Entry(name: "Mail", category: .messaging),
        "com.apple.mobilephone": Entry(name: "Phone", category: .messaging),
        "com.apple.facetime": Entry(name: "FaceTime", category: .messaging),
        "com.partiful.partiful": Entry(name: "Partiful", category: .messaging),
        "com.anthropic.claude": Entry(name: "Claude", category: .work),
        "com.anthropic.claudefordesktop": Entry(name: "Claude", category: .work),
        "com.openai.chat": Entry(name: "ChatGPT", category: .work),
        "com.apple.Terminal": Entry(name: "Terminal", category: .work),
        "com.googlecode.iterm2": Entry(name: "iTerm", category: .work),
        "com.apple.dt.Xcode": Entry(name: "Xcode", category: .work),
        "com.microsoft.VSCode": Entry(name: "VS Code", category: .work),
        "com.todesktop.230313mzl4w4u92": Entry(name: "Cursor", category: .work),
        "com.apple.Notes": Entry(name: "Notes", category: .work),
        "com.apple.mobilenotes": Entry(name: "Notes", category: .work),
        "com.apple.iCal": Entry(name: "Calendar", category: .work),
        "com.apple.mobilecal": Entry(name: "Calendar", category: .work),
        "com.notion.id": Entry(name: "Notion", category: .work),
        "notion.id": Entry(name: "Notion", category: .work),
        "com.linear": Entry(name: "Linear", category: .work),
        "com.figma.Desktop": Entry(name: "Figma", category: .work),
        "com.google.GoogleMobile": Entry(name: "Google", category: .other),
        "com.openai.codex": Entry(name: "Codex", category: .work),
        "com.apple.Preview": Entry(name: "Preview", category: .other),
        "scrollback.doomscroll": Entry(name: "Doomscroll apps", category: .social),
        "com.example.scrollback": Entry(name: "Scrollback", category: .other),
        "com.example.scrollback.mac": Entry(name: "Scrollback", category: .other),
        "com.apple.mobilesafari": Entry(name: "Safari", category: .other),
        "com.apple.Safari": Entry(name: "Safari", category: .other),
        "com.google.Chrome": Entry(name: "Chrome", category: .other),
        "com.google.chrome.ios": Entry(name: "Chrome", category: .other),
        "company.thebrowser.Browser": Entry(name: "Arc", category: .other),
        "com.spotify.client": Entry(name: "Spotify", category: .other),
        "com.withopal.opal": Entry(name: "Opal", category: .other),
        "com.apple.Preferences": Entry(name: "Settings", category: .other),
        "com.apple.systempreferences": Entry(name: "System Settings", category: .other),
        "com.apple.finder": Entry(name: "Finder", category: .other),
        "com.apple.mobiletimer": Entry(name: "Clock", category: .other),
        "com.apple.camera": Entry(name: "Camera", category: .other),
        "com.apple.mobileslideshow": Entry(name: "Photos", category: .other),
        "com.apple.Maps": Entry(name: "Maps", category: .other),
        "com.robinhood.release.Robinhood": Entry(name: "Robinhood", category: .other),
    ]

    public static func isSystemSurface(_ bundleID: String) -> Bool {
        systemSurfaces.contains(bundleID)
    }

    public static func category(for bundleID: String) -> AppCategory {
        known[bundleID]?.category ?? .other
    }

    public static func name(for bundleID: String) -> String {
        if let entry = known[bundleID] { return entry.name }
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}
