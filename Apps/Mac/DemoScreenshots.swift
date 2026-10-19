import AppKit
import SwiftUI
import ScrollbackCore

/// `-demo YES -renderScreenshots <folder>` draws the main window from demo data into PNGs, then quits.
/// It draws offscreen, so it needs no Screen Recording access and shows nothing on screen.
/// scripts/screenshots.sh runs it for the README images.
@MainActor
enum DemoScreenshots {
    static let windowSize = CGSize(width: 1120, height: 760)
    /// Long enough for app icons to load and the timeline to scroll into place.
    static let settleTime: Duration = .seconds(3)

    struct Shot {
        let name: String
        let device: DeviceKind
        let mode: ViewMode
        let appearance: NSAppearance.Name
        var selectsLatestBinge = false
    }

    static let shots = [
        Shot(name: "demo-mac-app-timeline", device: .iphone, mode: .timeline, appearance: .aqua, selectsLatestBinge: true),
        Shot(name: "demo-mac-app-dark", device: .mac, mode: .list, appearance: .darkAqua),
        Shot(name: "demo-mac-app-apps", device: .iphone, mode: .apps, appearance: .aqua),
    ]

    /// Only with demo data, so a render can never capture someone's real history.
    static var folder: URL? {
        guard Demo.isOn, let path = UserDefaults.standard.string(forKey: "renderScreenshots") else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    static func renderAndQuit(model: AppModel, into folder: URL) async {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            await model.refresh()
            await model.show(day: latestWholeWeekday())
            for shot in shots {
                model.clearFocus()
                model.device = shot.device
                model.viewMode = shot.mode
                if shot.selectsLatestBinge, let binge = model.report.binges.last(where: { $0.device == shot.device }) {
                    model.selection = .binge(binge)
                    await model.focus(on: DateInterval(start: binge.start, end: binge.end))
                }
                let url = folder.appending(path: "\(shot.name).png")
                try await render(MacRoot(model: model), appearance: shot.appearance, to: url)
                print("Wrote \(url.path)")
            }
            NSApp.terminate(nil)
        } catch {
            FileHandle.standardError.write(Data("Couldn't render screenshots: \(error)\n".utf8))
            exit(1)
        }
    }

    /// Today stops at whatever time the script runs, and the demo Mac only works on weekdays.
    private static func latestWholeWeekday() -> Date {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: .now)
        repeat {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day.addingTimeInterval(-86_400)
        } while calendar.isDateInWeekend(day)
        return day
    }

    enum Failure: Error {
        case noBitmap
        case noPNG
    }

    private static func render(_ view: some View, appearance: NSAppearance.Name, to url: URL) async throws {
        let hosting = NSHostingView(rootView: view.frame(width: windowSize.width, height: windowSize.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: windowSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: settleTime)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw Failure.noBitmap }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.noPNG }
        try png.write(to: url)
        window.contentView = nil
    }
}
