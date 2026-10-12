import Foundation

public enum Format {
    /// 47m · 1h 12m · 38s
    public static func duration(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    /// 12m 04s, for precise readouts where seconds matter.
    public static func preciseDuration(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        if m > 0 { return "\(m)m \(String(format: "%02d", s))s" }
        return "\(s)s"
    }

    public static func clock(_ d: Date, seconds: Bool = false) -> String {
        d.formatted(.dateTime.hour().minute())
            + (seconds ? String(format: ":%02d", Calendar.current.component(.second, from: d)) : "")
    }

    static let machine: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    /// "Sat Oct 11, 2:41am" so the on-device model can copy times verbatim instead of converting them.
    public static func spokenTime(_ d: Date) -> String {
        let day = d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let time = d.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute().locale(Locale(identifier: "en_US_POSIX")))
        return "\(day), \(time.replacingOccurrences(of: " ", with: "").lowercased())"
    }

    public static func machineTime(_ d: Date) -> String { machine.string(from: d) }
    public static func parseMachineTime(_ s: String) -> Date? { machine.date(from: s.trimmingCharacters(in: .whitespaces)) }
}
