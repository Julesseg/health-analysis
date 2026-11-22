import XCTest

final class SleepHistoryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWakeDatesCoverageAndCorrectedSleepAreVisibleInData() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_MEASUREMENT_UI_FIXTURE"] = "sleepHistory"
        app.launchEnvironment["HEALTH_MEASUREMENT_UI_FIXTURE_STORE"] = UUID().uuidString
        app.launch()

        app.tabBars.buttons["Data"].tap()
        app.buttons["Sleep"].tap()
        XCTAssertTrue(app.staticTexts["No readable sleep records"].waitForExistence(timeout: 5))

        app.navigationBars.buttons["Data"].tap()
        app.buttons["Health access and sources"].tap()
        app.buttons["Request read access"].tap()
        XCTAssertTrue(app.staticTexts["fixture.sleep.watch"].waitForExistence(timeout: 5))

        app.navigationBars.buttons["Data"].tap()
        app.buttons["Sleep"].tap()
        let gap = app.descendants(matching: .any)["health.coverage.daysWithoutMeasurements"].firstMatch
        show(gap, in: app)
        XCTAssertEqual(gap.value as? String, "1")

        let march31 = app.staticTexts.matching(identifier: "sleep.wakeDate")
            .containing(NSPredicate(format: "label CONTAINS %@", "Mar 31, 2026")).firstMatch
        let march29 = app.staticTexts.matching(identifier: "sleep.wakeDate")
            .containing(NSPredicate(format: "label CONTAINS %@", "Mar 29, 2026")).firstMatch
        show(march31, in: app)
        show(app.staticTexts["8 hours"], in: app)
        XCTAssertTrue(app.staticTexts["Fixture Watch"].firstMatch.exists)
        show(march29, in: app)
        show(app.staticTexts["7 hours"], in: app)

        let refresh = app.buttons["Refresh Health measurements"]
        for _ in 0..<6 where !refresh.isHittable { app.swipeDown() }
        XCTAssertTrue(refresh.isHittable)
        refresh.tap()

        show(app.staticTexts["6 hours"], in: app)
        XCTAssertTrue(march31.exists)
        XCTAssertFalse(app.staticTexts["8 hours"].exists)
    }

    @MainActor
    private func show(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
