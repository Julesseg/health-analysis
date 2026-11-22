import XCTest

final class HealthAnalysisUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsEmptyStatesAndOpensLogAndSettings() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
