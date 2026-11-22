import XCTest

final class ManualClockLogUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testConfigureClockAndReviewBackdatedApproximationAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launchEnvironment["HEALTH_ANALYSIS_MANUAL_LOG_TEST_STORE"] = UUID().uuidString
        app.launch()

        app.buttons["Settings"].tap()
        let addTime = app.buttons["Add time of day"]
        for _ in 0..<3 where !addTime.isHittable {
            app.swipeUp()
        }
        addTime.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let time = app.descendants(matching: .any).matching(identifier: "manual-clock-picker").firstMatch
        XCTAssertTrue(time.exists)
        app.buttons["Previous day"].tap()
        name.tap()
        name.typeText("Last caffeine")
        app.navigationBars["New time of day"].buttons["Add"].tap()
        let settings = app.navigationBars["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.buttons["Close"].tap()

        app.buttons["Log"].tap()
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        let approximate = app.switches["Approximate time for Last caffeine"]
        XCTAssertEqual(approximate.value as? String, "0")
        app.buttons["Previous day"].tap()
        app.buttons["Confirm day"].tap()
        XCTAssertTrue(app.staticTexts["Day reviewed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Assumed default"].exists)

        approximate.tap()
        XCTAssertEqual(approximate.value as? String, "1")
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review needed"].exists)
        app.buttons["Confirm day"].tap()
        XCTAssertTrue(app.staticTexts["Day reviewed"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        app.buttons["Log"].tap()
        XCTAssertTrue(approximate.waitForExistence(timeout: 5))
        XCTAssertEqual(approximate.value as? String, "0")
        XCTAssertTrue(app.staticTexts["Assumed default"].exists)
        app.buttons["Previous day"].tap()
        XCTAssertEqual(approximate.value as? String, "1")
        XCTAssertTrue(app.staticTexts["Saved"].exists)
        XCTAssertTrue(app.staticTexts["Day reviewed"].exists)
    }
}
