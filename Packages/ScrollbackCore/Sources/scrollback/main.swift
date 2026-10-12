import Foundation
import ScrollbackCore

// Usage: scrollback [today|yesterday|YYYY-MM-DD] [HH:MM-HH:MM]
let args = Array(CommandLine.arguments.dropFirst())
let calendar = Calendar.current

func day(from arg: String?) -> Date {
    let today = calendar.startOfDay(for: .now)
    switch arg {
    case nil, "today": return today
    case "yesterday": return calendar.date(byAdding: .day, value: -1, to: today)!
    case let s?:
        guard let date = Format.parseMachineTime("\(s) 00:00") else {
            FileHandle.standardError.write(Data("Unrecognized day \(s), use today, yesterday, or YYYY-MM-DD\n".utf8))
            exit(2)
        }
        return date
    }
}

func window(on day: Date, range: String?) -> DateInterval {
    guard let range, let dash = range.firstIndex(of: "-") else {
        return DateInterval(start: day, end: calendar.date(byAdding: .day, value: 1, to: day)!)
    }
    func time(_ s: Substring) -> Date {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard let h = parts.first, (0...24).contains(h) else {
            FileHandle.standardError.write(Data("Unrecognized time \(s), use HH:MM\n".utf8))
            exit(2)
        }
        return day.addingTimeInterval(TimeInterval(h * 3600 + (parts.count > 1 ? parts[1] : 0) * 60))
    }
    let from = time(range[..<dash])
    var to = time(range[range.index(after: dash)...])
    if to <= from { to = to.addingTimeInterval(86_400) }
    return DateInterval(start: from, end: to)
}

func clock(_ d: Date) -> String { d.formatted(Date.VerbatimFormatStyle(format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)", timeZone: .current, calendar: .current)) }
func dur(_ t: TimeInterval) -> String {
    let m = Int(t) / 60, s = Int(t) % 60
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : m > 0 ? "\(m)m \(s)s" : "\(s)s"
}

let store = try SessionStore(url: SessionStore.defaultURL())
let result = try BiomeSource().load()
result.warnings.forEach { print("warning: \($0)") }
let ingested = result.sessions
var added = try await store.upsert(ingested.filter { $0.device == .iphone })
if let window = result.coverage(for: .mac) {
    added += try await store.replace(device: .mac, in: window, with: ingested.filter { $0.device == .mac })
}
print("ingested \(ingested.count) sessions · store holds \(try await store.count()) (\(added >= 0 ? "+" : "")\(added))")

if args.first == "ask" {
    let question = args.dropFirst().joined(separator: " ")
    let answer = try await Asker(store: store).ask(question)
    print("\nQ: \(question)\nA: \(answer.text)")
    for w in answer.windows { print("   looked at \(Format.machineTime(w.start)) → \(Format.machineTime(w.end))") }
    exit(0)
}

let dayArg = args.first { !$0.contains(":") }
let rangeArg = args.first { $0.contains(":") }
let win = window(on: day(from: dayArg), range: rangeArg)
let sessions = try await store.sessions(overlapping: win).compactMap { $0.clipped(to: win) }

for device in DeviceKind.allCases {
    let mine = sessions.filter { $0.device == device }
    guard !mine.isEmpty else { continue }
    let total = mine.reduce(0) { $0 + $1.duration }
    print("\n\(device.rawValue.uppercased()) · \(dur(total)) total")
    let byApp = Dictionary(grouping: mine, by: \.bundleID).mapValues { $0.reduce(0) { $0 + $1.duration } }
    for (id, t) in byApp.sorted(by: { $0.value > $1.value }).prefix(8) {
        print("  \(AppCatalog.name(for: id).padding(toLength: 16, withPad: " ", startingAt: 0)) \(dur(t))")
    }
}

let binges = BingeDetector.binges(in: sessions)
print("\nBINGES (\(binges.count))")
for b in binges {
    let hops = b.hops.map(AppCatalog.name(for:)).joined(separator: " → ")
    print("  \(b.device.rawValue) \(clock(b.start))–\(clock(b.end))  \(dur(b.span))  \(hops)")
}

if rangeArg != nil {
    print("\nLOG")
    for s in sessions {
        print("  \(clock(s.start))  \(s.device.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) \(AppCatalog.name(for: s.bundleID).padding(toLength: 14, withPad: " ", startingAt: 0)) \(dur(s.duration).padding(toLength: 8, withPad: " ", startingAt: 0)) \(s.reason?.label ?? "")")
    }
}
