import XCTest

final class FirstUseUITests: XCTestCase {
    @MainActor
    func testSkipsManualSetupAndEditsAReadablePresetInExplore() {
        let app = launchFirstUse()
        let sleep = app.descendants(matching: .any)["firstUse.coverage.sleepAnalysis"].firstMatch
        XCTAssertTrue(sleep.waitForExistence(timeout: 5))
        XCTAssertTrue(sleep.label.contains("No readable sleep records")
            || (sleep.value as? String)?.contains("No readable sleep records") == true)

        app.buttons["Review manual tracking"].tap()
        XCTAssertTrue(app.navigationBars["Manual tracking"].waitForExistence(timeout: 5))
        app.buttons["Continue to Explore"].tap()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 5))

        let suggestions = app.buttons["Suggested questions"]
        for _ in 0..<3 where !suggestions.isHittable { app.swipeUp() }
        suggestions.tap()
        let preset = app.buttons["Resting heart rate with Workout duration"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[
            "Analysis unavailable until the original HRV measure and how it was summarized are verified."
        ].exists)
        preset.tap()

        let inputs = app.descendants(matching: .any)["explore.inputs"].firstMatch
        XCTAssertTrue(inputs.waitForExistence(timeout: 5))
        XCTAssertTrue(inputs.label.contains("Workout duration") || (inputs.value as? String) == "Workout duration")
        let history = app.descendants(matching: .any)["explore.history"].firstMatch
        history.tap()
        app.descendants(matching: .any)["Last 90 days"].firstMatch.tap()

        let analyze = app.buttons["Analyze"]
        for _ in 0..<3 where !analyze.isHittable { app.swipeUp() }
        analyze.tap()
        XCTAssertTrue(app.navigationBars["Analysis result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Confidence"].waitForExistence(timeout: 5))
        let resultHistory = app.descendants(matching: .any)["explore.result.history"].firstMatch
        for _ in 0..<5 where !resultHistory.isHittable { app.swipeUp() }
        XCTAssertTrue(resultHistory.label.contains("Last 90 days") || (resultHistory.value as? String) == "Last 90 days")
    }

    @MainActor
    func testSavesAnEditedSuggestedDefaultDuringSetup() {
        let app = launchFirstUse()
        app.buttons["Review manual tracking"].tap()
        let caffeine = app.buttons["Caffeine"]
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5))
        caffeine.tap()

        let defaultValue = app.textFields["Default value"]
        XCTAssertTrue(defaultValue.waitForExistence(timeout: 5))
        defaultValue.tap()
        defaultValue.typeText(XCUIKeyboardKey.delete.rawValue + "75")
        app.buttons["Add"].tap()

        let continueButton = app.buttons["Continue to Explore"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()
        app.buttons["Log"].tap()
        let caffeineEntry = app.textFields["Caffeine"]
        XCTAssertTrue(caffeineEntry.waitForExistence(timeout: 5))
        XCTAssertEqual(caffeineEntry.value as? String, "75")
    }

    @MainActor
    private func launchFirstUse() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_FIRST_USE_UI_FIXTURE"] = "1"
        app.launch()

        let entry = app.buttons["Get started"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.staticTexts[
            "Health Analysis reads Apple Health to show your measurements and explore how they relate to your tracked behaviors. It keeps your data on this device."
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Access is read-only. Health Analysis doesn’t write to Apple Health."].exists)
        app.buttons["Request read access"].tap()
        let review = app.buttons["Review manual tracking"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        let coverage = app.descendants(matching: .any)["firstUse.coverage.restingHeartRate"].firstMatch
        XCTAssertTrue(coverage.waitForExistence(timeout: 5))
        XCTAssertTrue(coverage.label.contains("Days without measurements in this range")
            || (coverage.value as? String)?.contains("Days without measurements in this range") == true)
        return app
    }
}
