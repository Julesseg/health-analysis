import XCTest

final class ActivityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRunningHistoryShowsObservedZeroGapsAndSourcesAfterRepeatedImport() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_MEASUREMENT_UI_FIXTURE"] = "workouts"
        app.launchEnvironment["HEALTH_MEASUREMENT_UI_FIXTURE_STORE"] = UUID().uuidString
        app.launch()

        app.tabBars.buttons["Data"].tap()
        app.buttons["Running distance"].tap()
        XCTAssertTrue(app.staticTexts["No readable workouts for this variable"].waitForExistence(timeout: 5))
        app.buttons["Health access and sources"].tap()
        app.buttons["Request read access"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        let sourcePicker = app.descendants(matching: .any)["activity.preferredSource"].firstMatch
        XCTAssertTrue(sourcePicker.waitForExistence(timeout: 5))
        sourcePicker.tap()
        let bridge = app.descendants(matching: .any)["Bridge (fixture.bridge)"].firstMatch
        XCTAssertTrue(bridge.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Watch (fixture.watch)"].firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()

        let refresh = app.buttons["Refresh Health measurements"]
        for _ in 0..<3 where !refresh.isHittable { app.swipeDown() }
        refresh.tap()

        let days = app.buttons.matching(identifier: "activity.day")
        let earlierDay = days.element(boundBy: 1)
        for _ in 0..<5 where !earlierDay.isHittable { app.swipeUp() }
        XCTAssertTrue(earlierDay.isHittable)
        let gaps = app.descendants(matching: .any)["activity.coverage.gaps"].firstMatch
        XCTAssertTrue(gaps.exists)
        XCTAssertEqual(days.count, 2)

        earlierDay.tap()
        let dailyTotal = app.staticTexts["activity.dailyTotal"]
        XCTAssertTrue(dailyTotal.waitForExistence(timeout: 5))
        XCTAssertEqual(dailyTotal.label, "0 feet")
        app.navigationBars.buttons.firstMatch.tap()

        let latestDay = days.firstMatch
        XCTAssertTrue(latestDay.isHittable)
        latestDay.tap()
        XCTAssertTrue(dailyTotal.waitForExistence(timeout: 5))
        XCTAssertEqual(dailyTotal.label, "3.107 miles")
        for identifier in ["fixture.bridge", "fixture.watch"] {
            let source = app.staticTexts[identifier]
            for _ in 0..<3 where !source.isHittable { app.swipeUp() }
            XCTAssertTrue(source.isHittable)
        }
    }
}
