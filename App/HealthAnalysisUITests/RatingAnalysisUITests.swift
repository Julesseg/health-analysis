import XCTest

final class RatingAnalysisUITests: XCTestCase {
    @MainActor
    func testEditsAnOrderedRatingAndExploresTheThresholdComparison() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_RATING_UI_FIXTURE"] = "1"
        app.launch()

        app.buttons["Log"].tap()
        let stressEntry = app.steppers.matching(NSPredicate(format: "label BEGINSWITH %@", "Stress")).firstMatch
        XCTAssertTrue(stressEntry.waitForExistence(timeout: 5))
        app.buttons["Previous day"].tap()
        app.buttons["Previous day"].tap()
        XCTAssertEqual(stressEntry.value as? String, "2")
        stressEntry.buttons["Increment"].tap()
        XCTAssertEqual(stressEntry.value as? String, "3")
        app.navigationBars["Log"].buttons["Close"].tap()

        app.tabBars.buttons["Explore"].tap()
        let output = app.descendants(matching: .any)["explore.output"].firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        output.tap()
        let energy = app.descendants(matching: .any)["Energy (rating 1 to 5)"].firstMatch
        XCTAssertTrue(energy.waitForExistence(timeout: 5))
        energy.tap()

        app.descendants(matching: .any)["explore.inputs"].firstMatch.tap()
        let stress = app.switches["Stress (rating 1 to 5)"]
        XCTAssertTrue(stress.waitForExistence(timeout: 5))
        stress.tapExploreSwitch()
        app.navigationBars["Inputs"].buttons.firstMatch.tap()

        let analyze = app.buttons["Analyze"]
        for _ in 0..<4 where !analyze.isHittable { app.swipeUp() }
        analyze.tap()
        let effect = app.staticTexts["explore.ratingEffect"]
        XCTAssertTrue(effect.waitForExistence(timeout: 5))
        XCTAssertTrue(effect.label.contains("percentage points"))
        XCTAssertTrue(effect.label.contains("Energy at 3 or above"))
        XCTAssertTrue(effect.label.contains("Stress at 3 or above vs. below 3"))
        let chart = app.descendants(matching: .any)["explore.estimateChart"].firstMatch
        XCTAssertTrue(chart.exists)
        XCTAssertTrue((chart.value as? String)?.contains("Stress at 3 or above vs. below 3") == true)
        XCTAssertEqual(app.descendants(matching: .any)["explore.confidence"].firstMatch.value as? String, "Low")

        let evidence = app.buttons["Model and evidence"]
        for _ in 0..<10 where !evidence.isHittable { app.swipeUp() }
        evidence.tap()
        XCTAssertTrue(app.navigationBars["Model and evidence"].waitForExistence(timeout: 5))
        let levels = app.staticTexts["Recorded at 3 or above"].firstMatch
        for _ in 0..<5 where !levels.isHittable { app.swipeUp() }
        XCTAssertTrue(levels.exists)
    }
}
