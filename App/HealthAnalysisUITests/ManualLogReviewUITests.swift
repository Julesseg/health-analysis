import XCTest

final class ManualLogReviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReviewADayAndChooseWhenDefaultsApply() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_MANUAL_LOG_TEST_STORE"] = UUID().uuidString
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["Add quantity"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.buttons["Previous day"].tap()
        name.tap()
        name.typeText("Caffeine")
        let unit = app.textFields["Unit"]
        unit.tap()
        unit.typeText("mg")
        let defaultValue = app.textFields["Default value"]
        defaultValue.tap()
        defaultValue.typeText("25")
        app.navigationBars["New quantity"].buttons["Add"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars["Settings"].buttons["Close"].tap()

        app.buttons["Log"].tap()
        let quantity = app.textFields["Caffeine (mg)"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        app.buttons["Previous day"].tap()
        XCTAssertEqual(quantity.value as? String, "25")
        XCTAssertTrue(app.staticTexts["Day not reviewed"].exists)
        app.buttons["Confirm day"].tap()
        XCTAssertTrue(app.staticTexts["Day reviewed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Assumed default"].exists)
        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.staticTexts["No tracking variables for this date"].exists)
        app.navigationBars["Log"].buttons["Close"].tap()

        app.buttons["Settings"].tap()
        app.buttons["Caffeine"].tap()
        XCTAssertTrue(app.staticTexts["Default history"].waitForExistence(timeout: 5))
        app.buttons["Change default"].tap()
        XCTAssertTrue(defaultValue.waitForExistence(timeout: 5))
        defaultValue.tap()
        defaultValue.typeText("75")
        app.navigationBars["Change default"].buttons["Save"].tap()
        let fillOlderHistory = app.buttons["Fill older history"]
        XCTAssertTrue(fillOlderHistory.waitForExistence(timeout: 5))
        fillOlderHistory.tap()
        XCTAssertTrue(defaultValue.waitForExistence(timeout: 5))
        defaultValue.tap()
        defaultValue.typeText("10")
        app.navigationBars["Fill older history"].buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Change default"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        app.buttons["Log"].tap()
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertEqual(quantity.value as? String, "75")
        XCTAssertTrue(app.staticTexts["Day not reviewed"].exists)
        app.buttons["Previous day"].tap()
        XCTAssertEqual(quantity.value as? String, "25")
        XCTAssertTrue(app.staticTexts["Day reviewed"].exists)
        XCTAssertTrue(app.staticTexts["Assumed default"].exists)
        app.buttons["Previous day"].tap()
        XCTAssertEqual(quantity.value as? String, "10")
        XCTAssertTrue(app.staticTexts["Day not reviewed"].exists)
        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.staticTexts["No tracking variables for this date"].exists)
    }
}
