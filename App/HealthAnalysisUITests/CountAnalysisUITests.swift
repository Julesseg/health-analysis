import XCTest

final class CountAnalysisUITests: XCTestCase {
    @MainActor
    func testSelectsStoredCountsAndInspectsCountOutcomeUncertaintyAndCoverage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_COUNT_UI_FIXTURE"] = "1"
        app.launch()

        app.tabBars.buttons["Explore"].tap()
        let output = app.descendants(matching: .any)["explore.output"].firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        output.tap()
        let headaches = app.descendants(matching: .any)["Headaches (count)"].firstMatch
        XCTAssertTrue(headaches.waitForExistence(timeout: 5))
        headaches.tap()

        app.descendants(matching: .any)["explore.inputs"].firstMatch.tap()
        let coffees = app.switches["Coffees (count)"]
        XCTAssertTrue(coffees.waitForExistence(timeout: 5))
        coffees.tapExploreSwitch()
        XCTAssertFalse(app.switches["Headaches (count)"].exists)
        app.navigationBars["Inputs"].buttons.firstMatch.tap()

        let analyze = app.buttons["Analyze"]
        for _ in 0..<3 where !analyze.isHittable { app.swipeUp() }
        XCTAssertTrue(analyze.isEnabled)
        analyze.tap()
        let effect = app.staticTexts["explore.countEffect"]
        XCTAssertTrue(effect.waitForExistence(timeout: 5))
        XCTAssertTrue(effect.label.contains("%") && effect.label.contains("expected daily count"))
        XCTAssertTrue(app.descendants(matching: .any)["explore.uncertainty"].firstMatch.exists)

        let coverage = app.buttons["Usable dates and gaps"]
        for _ in 0..<10 where !coverage.isHittable { app.swipeUp() }
        XCTAssertTrue(coverage.isHittable)
        coverage.tap()
        XCTAssertTrue(app.navigationBars["Usable dates and gaps"].waitForExistence(timeout: 5))
        let pair = app.buttons.matching(identifier: "explore.pairedCounts").firstMatch
        for _ in 0..<4 where !pair.isHittable { app.swipeUp() }
        XCTAssertTrue(pair.isHittable)
        pair.tap()
        XCTAssertTrue(app.navigationBars["Paired counts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recorded count"].firstMatch.exists)
    }
}
