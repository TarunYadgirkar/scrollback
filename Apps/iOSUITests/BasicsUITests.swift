import XCTest

/// Drives the installed app the way a person would: scroll, tap every control, leave, come back, relaunch.
/// Run on the phone with scripts/test-phone.sh; Screen Time access must already be granted there.
final class BasicsUITests: XCTestCase {
    private let app = XCUIApplication()
    private static let timeout: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
        // Argument-domain defaults override the remembered choices, so every test starts on the iPhone list.
        // -uiTesting keeps the notification prompt from covering the screen mid-test.
        app.launchArguments = ["-viewMode", "list", "-device", "iphone", "-uiTesting"]
        app.launch()
        XCTAssertTrue(activityTitle.waitForExistence(timeout: Self.timeout), "Main screen never appeared (stuck on setup?)")
        snap("launched")
    }

    private var activityTitle: XCUIElement { app.staticTexts["Activity"] }

    private func button(startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Swipes the page until the element can be tapped.
    private func reveal(_ element: XCUIElement, up: Bool = true) {
        for _ in 0..<10 where !element.isHittable {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: up ? 0.75 : 0.3))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: up ? 0.35 : 0.7)))
        }
        XCTAssertTrue(element.isHittable, "Couldn't scroll to \(element)")
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTodayReportScrolls() {
        // iOS hands touches on a Screen Time report to Screen Time, so the report has to scroll itself.
        let byHour = app.staticTexts["By hour"]
        XCTAssertTrue(byHour.waitForExistence(timeout: Self.timeout), "Screen Time report never loaded")
        let before = byHour.frame.minY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        XCTAssertLessThan(byHour.frame.minY, before, "Swiping the Screen Time report didn't scroll it")
        snap("report scrolled")
        XCTAssertTrue(button(startingWith: "iPhone").isHittable, "Header scrolled away with the report")
    }

    func testDeviceTabsAndDays() {
        button(startingWith: "Mac").tap()
        XCTAssertTrue(button(startingWith: "Mac").isSelected)
        snap("mac tab")

        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.buttons["Back to today"].waitForExistence(timeout: Self.timeout))
        snap("yesterday on mac")
        app.buttons["Back to today"].tap()
        XCTAssertTrue(button(startingWith: "Today").waitForExistence(timeout: Self.timeout))

        button(startingWith: "iPhone").tap()
        XCTAssertTrue(button(startingWith: "iPhone").isSelected)
        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.buttons["Back to today"].waitForExistence(timeout: Self.timeout))
        snap("yesterday on iphone")
        app.buttons["Back to today"].tap()
    }

    func testDayPickerOpensAndCloses() {
        button(startingWith: "Today").tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: Self.timeout))
        snap("day picker")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        XCTAssertTrue(activityTitle.waitForExistence(timeout: Self.timeout))
    }

    func testTimelineFitsOnScreen() {
        app.buttons["Timeline"].tap()
        XCTAssertTrue(button(startingWith: "iPhone").waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(button(startingWith: "iPhone").isHittable, "Timeline header pushed the tabs off screen")
        let ribbon = app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height }
        XCTAssertGreaterThan(ribbon?.frame.height ?? 0, 250, "Timeline has no room to show the day")
        snap("timeline")
        ribbon?.swipeUp()
        ribbon?.swipeDown()
        app.buttons["List"].tap()
        XCTAssertTrue(app.staticTexts["By hour"].waitForExistence(timeout: Self.timeout))
    }

    func testRowsExpand() {
        button(startingWith: "Mac").tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '–'")).firstMatch
        guard row.waitForExistence(timeout: 5) else { return }
        reveal(row)
        row.tap()
        snap("row expanded")
        row.tap()
    }

    func testSyncPillAndAskChip() {
        button(startingWith: "Synced").exists ? button(startingWith: "Synced").tap() : button(startingWith: "Mac not nearby").tap()
        let chip = app.buttons["How much social today?"]
        guard chip.waitForExistence(timeout: 5) else { return }
        chip.tap()
        let dismiss = app.buttons["Dismiss answer"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 60), "Ask never answered")
        snap("ask answer")
        dismiss.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: Self.timeout))
    }

    func testLeaveAndComeBack() {
        XCUIDevice.shared.press(.home)
        // iOS may go straight to suspended, so accept any state that isn't on screen.
        let left = expectation(for: NSPredicate { app, _ in (app as? XCUIApplication)?.state != .runningForeground }, evaluatedWith: app)
        wait(for: [left], timeout: Self.timeout)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: Self.timeout))
        XCTAssertTrue(activityTitle.waitForExistence(timeout: Self.timeout), "Main screen gone after coming back")
        snap("back from home")
    }

    func testKillAndRelaunch() {
        app.terminate()
        app.launch()
        XCTAssertTrue(activityTitle.waitForExistence(timeout: Self.timeout), "Relaunch landed on setup instead of the main screen")
        snap("relaunched")
    }
}
