import XCTest

final class ManualLogUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateQuantityAndRevisitBackdatedAutosaveAfterRelaunch() {
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
        defaultValue.typeText("37.5")
        app.navigationBars["New quantity"].buttons["Add"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars["Settings"].buttons["Close"].tap()

        app.buttons["Log"].tap()
        let quantity = app.textFields["Caffeine (mg)"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertEqual(quantity.value as? String, "37.5")
        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.staticTexts["Assumed default"].exists)
        XCTAssertEqual(quantity.value as? String, "37.5")
        quantity.tap()
        quantity.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        XCTAssertTrue(app.staticTexts["Enter a number."].waitForExistence(timeout: 5))
        quantity.typeText("0")
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 5))
        app.navigationBars["Log"].buttons["Close"].tap()

        app.buttons["Log"].tap()
        XCTAssertEqual(quantity.value as? String, "37.5")
        app.buttons["Previous day"].tap()
        XCTAssertEqual(quantity.value as? String, "0")

        app.terminate()
        app.launch()
        app.buttons["Log"].tap()
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertEqual(quantity.value as? String, "37.5")
        app.buttons["Previous day"].tap()
        XCTAssertEqual(quantity.value as? String, "0")
        XCTAssertTrue(app.staticTexts["Saved"].exists)
    }
}
