import XCTest

final class ClockAnalysisUITests: XCTestCase {
    @MainActor
    func testSelectsClockTimesAcrossMidnightAndInspectsRecordedPrecision() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_CLOCK_UI_FIXTURE"] = "1"
        app.launch()

        app.tabBars.buttons["Explore"].tap()
        let output = app.descendants(matching: .any)["explore.output"].firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        output.tap()
        let bedtime = app.descendants(matching: .any)["Bedtime (time of day)"].firstMatch
        XCTAssertTrue(bedtime.waitForExistence(timeout: 5))
        bedtime.tap()

        app.descendants(matching: .any)["explore.inputs"].firstMatch.tap()
        let caffeine = app.switches["Last caffeine (time of day)"]
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5))
        caffeine.tapExploreSwitch()
        app.navigationBars["Inputs"].buttons.firstMatch.tap()
        let window = app.descendants(matching: .any)["explore.behaviorWindow"].firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(window.label.contains("Complete preceding day") || (window.value as? String)?.contains("Complete preceding day") == true)
        XCTAssertFalse(app.descendants(matching: .any)["explore.interaction"].firstMatch.exists)

        let analyze = app.buttons["Analyze"]
        for _ in 0..<4 where !analyze.isHittable { app.swipeUp() }
        XCTAssertTrue(analyze.isHittable)
        analyze.tap()
        let effect = app.staticTexts["explore.clockEffect"]
        XCTAssertTrue(effect.waitForExistence(timeout: 5))
        XCTAssertTrue(effect.label.contains("30 minutes per hour later"))
        XCTAssertTrue(app.descendants(matching: .any)["explore.uncertainty"].firstMatch.exists)
        let save = app.buttons["analysis.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["analysis.pin"].waitForExistence(timeout: 5))

        let coverage = app.buttons["Usable dates and gaps"]
        for _ in 0..<10 where !coverage.isHittable { app.swipeUp() }
        XCTAssertTrue(coverage.isHittable)
        coverage.tap()
        XCTAssertTrue(app.navigationBars["Usable dates and gaps"].waitForExistence(timeout: 5))
        let pair = app.buttons.matching(identifier: "explore.pairedClock").firstMatch
        for _ in 0..<6 where !pair.isHittable { app.swipeUp() }
        XCTAssertTrue(pair.isHittable)
        pair.tap()
        XCTAssertTrue(app.navigationBars["Paired values"].waitForExistence(timeout: 5))
        let precision = app.descendants(matching: .any)["explore.clockPrecision"].firstMatch
        XCTAssertTrue(precision.waitForExistence(timeout: 5))
        XCTAssertTrue(precision.label.contains("Approximate time") || (precision.value as? String)?.contains("Approximate time") == true)
    }
}
