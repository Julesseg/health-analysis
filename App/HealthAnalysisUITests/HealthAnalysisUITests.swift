import XCTest

final class HealthAnalysisUITests: XCTestCase {
    @MainActor
    func testEmptyLibraryNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let tabs = app.tabBars
        XCTAssertTrue(tabs.buttons["Analysis"].isSelected)
        XCTAssertEqual(tabs.buttons.count, 2)
        XCTAssertTrue(app.staticTexts["No saved analyses yet."].exists)
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped, .sufficientElementDescription])
        capture("Analysis", app)

        app.buttons["New Analysis"].tap()
        XCTAssertTrue(app.navigationBars["New Analysis"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Inputs"].exists)
        XCTAssertTrue(app.staticTexts["Output"].exists)
        capture("New Analysis", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Discover"].tap()
        XCTAssertTrue(app.navigationBars["Discover"].waitForExistence(timeout: 5))
        capture("Discover", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("Settings", app)
        app.buttons["Done"].tap()
        tabs.buttons["Log"].tap()
        let today = app.buttons["logDay-0"]
        XCTAssertTrue(today.isSelected)
        XCTAssertTrue(app.staticTexts["No tracking variables configured."].exists)
        capture("Log", app)
        let dateHeader = app.staticTexts["selectedLogDate"]
        let todayLabel = dateHeader.label
        let center = CGVector(dx: 0.5, dy: 0.5)
        let start = app.buttons["logDay-5"].coordinate(withNormalizedOffset: center)
        let end = app.buttons["logDay-1"].coordinate(withNormalizedOffset: center)
        start.press(forDuration: 0.1, thenDragTo: end)
        let earlier = app.buttons["logDay-7"]
        earlier.tap()
        XCTAssertTrue(earlier.isSelected)
        XCTAssertNotEqual(dateHeader.label, todayLabel)
        capture("Backdated Log", app)
        tabs.buttons["Analysis"].tap()
        tabs.buttons["Log"].tap()
        XCTAssertTrue(today.isSelected)
    }

    @MainActor
    private func capture(_ screen: String, _ app: XCUIApplication) {
        guard ProcessInfo.processInfo.environment["CAPTURE_SCREENSHOTS"] == "true" else { return }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = screen
        image.lifetime = .keepAlways
        add(image)
    }
}
