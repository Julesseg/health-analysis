import XCTest

final class HealthAnalysisUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsEmptyStatesAndOpensLogAndSettings() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_MEASUREMENT_UI_FIXTURE"] = "empty"
        app.launchEnvironment["HEALTH_MEASUREMENT_UI_FIXTURE_STORE"] = UUID().uuidString
        app.launchEnvironment["HEALTH_ANALYSIS_MANUAL_LOG_TEST_STORE"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.staticTexts["No followed analyses yet"].waitForExistence(timeout: 10))

        let tabs = app.tabBars
        tabs.buttons["Explore"].tap()
        XCTAssertTrue(app.staticTexts["No variables to explore"].waitForExistence(timeout: 5))

        app.buttons["Log"].tap()
        XCTAssertTrue(app.staticTexts["No tracking variables"].waitForExistence(timeout: 5))
        app.navigationBars["Log"].buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["No variables to explore"].waitForExistence(timeout: 5))

        tabs.buttons["Data"].tap()
        XCTAssertTrue(app.staticTexts["No readable measurements"].waitForExistence(timeout: 5))

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars["Settings"].buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["No readable measurements"].waitForExistence(timeout: 5))

        tabs.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["No followed analyses yet"].waitForExistence(timeout: 5))
    }
}
