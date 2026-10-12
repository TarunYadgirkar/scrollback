import SwiftUI
import ScrollbackCore

/// Every color in the app. Signal is reserved for social/doomscroll time.
enum Palette {
    static let ink = Color(light: 0x16181B, dark: 0xECEAEB)
    static let inkMuted = Color(light: 0x6E686B, dark: 0x9A9598)
    static let inkFaint = Color(light: 0xA8A2A5, dark: 0x5F5B5E)
    static let surface = Color(light: 0xF4F3F4, dark: 0x111213)
    static let raised = Color(light: 0xFFFFFF, dark: 0x1A1B1D)
    static let rule = Color(light: 0xE4E1E3, dark: 0x2A2A2D)
    static let signal = Color(light: 0xD6336C, dark: 0xF0517F)
    static let messaging = Color(light: 0x2F8F83, dark: 0x45B3A5)
    static let work = Color(light: 0x3E6A8A, dark: 0x6E9CBF)
    static let idle = Color(light: 0xB9B3B6, dark: 0x4C494B)
    static let critical = Color(light: 0xB42318, dark: 0xF97066)

    static func category(_ category: AppCategory) -> Color {
        switch category {
        case .social: signal
        case .messaging: messaging
        case .work: work
        case .other: idle
        }
    }
}

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let block: CGFloat = 2
    static let control: CGFloat = 8
    static let card: CGFloat = 12
}

enum Motion {
    static let quick = Animation.easeOut(duration: 0.15)
}

/// SF Pro Expanded for readouts, SF Pro for text, SF Mono for clock times.
enum TypeScale {
    #if os(iOS)
    static let base: CGFloat = 15
    #else
    static let base: CGFloat = 13
    #endif

    #if os(iOS)
    static let readout = Font.system(size: base * 1.6, weight: .heavy).width(.expanded)
    #else
    static let readout = Font.system(size: base * 2, weight: .heavy).width(.expanded)
    #endif
    static let readoutSmall = Font.system(size: base * 1.25, weight: .bold).width(.expanded)
    static let title = Font.system(size: base * 1.15, weight: .semibold)
    static let body = Font.system(size: base)
    static let bodyStrong = Font.system(size: base, weight: .semibold)
    static let label = Font.system(size: base * 0.85, weight: .medium)
    static let mono = Font.system(size: base * 0.85, design: .monospaced).monospacedDigit()
    static let monoSmall = Font.system(size: base * 0.75, design: .monospaced).monospacedDigit()
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
        #else
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }
}

private func components(_ rgb: UInt32) -> (CGFloat, CGFloat, CGFloat) {
    (CGFloat((rgb >> 16) & 0xFF) / 255, CGFloat((rgb >> 8) & 0xFF) / 255, CGFloat(rgb & 0xFF) / 255)
}

#if os(macOS)
extension NSColor {
    convenience init(rgb: UInt32) {
        let (r, g, b) = components(rgb)
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
#else
extension UIColor {
    convenience init(rgb: UInt32) {
        let (r, g, b) = components(rgb)
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
#endif

struct PressScale: ButtonStyle {
    static let pressed: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressed : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

extension DeviceKind {
    var label: String { self == .iphone ? "iPhone" : "Mac" }
}

extension Date {
    /// 7pm, 12am. Compact hour labels for the ribbon gutter.
    var hourLabel: String {
        let hour = Calendar.current.component(.hour, from: self)
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12)\(hour < 12 ? "am" : "pm")"
    }

    /// 7:35pm
    var shortClock: String {
        formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute().locale(Locale(identifier: "en_US_POSIX")))
            .filter { !$0.isWhitespace }
            .lowercased()
    }

    /// 7:35:14pm
    var preciseClock: String {
        formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute().second().locale(Locale(identifier: "en_US_POSIX")))
            .filter { !$0.isWhitespace }
            .lowercased()
    }
}
