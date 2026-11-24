import XCTest

final class HealthAnalysisUITests: XCTestCase {
    @MainActor
    func testEmptyLibraryNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let tabs = app.tabBars
        XCTAssertTrue(tabs.buttons["Insights"].isSelected)
        for message in ["No saved analyses yet.", "No patterns to show yet.", "No measurements available."] {
            XCTAssertTrue(app.staticTexts[message].exists)
        }

        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped, .sufficientElementDescription])
        capture("Insights", app)
        tabs.buttons["Explore"].tap()
        XCTAssertTrue(app.staticTexts["No variables to explore"].exists)
        capture("Explore", app)
        app.buttons["Log"].tap()
        XCTAssertTrue(app.datePickers["Day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No tracking variables configured."].exists)
        capture("Log", app)
        app.buttons["Done"].tap()
        XCTAssertTrue(tabs.buttons["Explore"].isSelected)

        tabs.buttons["Data"].tap()
        XCTAssertTrue(app.staticTexts["No measurements available."].exists)
        capture("Data", app)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("Settings", app)
        app.buttons["Done"].tap()
        XCTAssertTrue(tabs.buttons["Data"].isSelected)
    }

    @MainActor
    private func capture(_ screen: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = screen
        image.lifetime = .keepAlways
        add(image)
    }
}
