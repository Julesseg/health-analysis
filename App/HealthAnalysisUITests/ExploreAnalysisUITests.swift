import XCTest

final class ExploreAnalysisUITests: XCTestCase {
    @MainActor
    func testBuildsCaffeineQuestionShowsAssociationAndPreservesSelections() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_EXPLORE_UI_FIXTURE"] = "1"
        app.launch()

        app.tabBars.buttons["Data"].tap()
        app.buttons["Health access and sources"].tap()
        app.buttons["Request read access"].tap()
        XCTAssertTrue(app.staticTexts["fixture.explore"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Explore"].tap()
        let output = app.descendants(matching: .any)["explore.output"].firstMatch
        let inputs = app.descendants(matching: .any)["explore.inputs"].firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["explore.adjustments"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["explore.behaviorWindow"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["explore.history"].firstMatch.exists)

        output.tap()
        let heartRate = app.descendants(matching: .any)["Resting heart rate"].firstMatch
        XCTAssertTrue(heartRate.waitForExistence(timeout: 5))
        heartRate.tap()
        inputs.tap()
        let caffeine = app.descendants(matching: .any)["Caffeine (mg)"].firstMatch
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5))
        caffeine.tap()

        let analyze = app.buttons["Analyze"]
        for _ in 0..<3 where !analyze.isHittable { app.swipeUp() }
        analyze.tap()
        XCTAssertTrue(app.staticTexts["Higher caffeine amounts were associated with higher resting heart rate."]
            .waitForExistence(timeout: 5))
        let interval = app.descendants(matching: .any)["explore.uncertainty"].firstMatch
        XCTAssertTrue(interval.exists)
        let chart = app.descendants(matching: .any)["explore.estimateChart"].firstMatch
        for _ in 0..<3 where !chart.isHittable { app.swipeUp() }
        XCTAssertTrue(chart.isHittable)
        let coverage = app.buttons["Usable dates and gaps"]
        for _ in 0..<4 where !coverage.isHittable { app.swipeUp() }
        XCTAssertTrue(coverage.isHittable)
        coverage.tap()
        XCTAssertTrue(app.navigationBars["Usable dates and gaps"].waitForExistence(timeout: 5))
        app.navigationBars["Usable dates and gaps"].buttons.firstMatch.tap()
        app.navigationBars["Analysis result"].buttons.firstMatch.tap()
        XCTAssertTrue(analyze.isEnabled)
        XCTAssertTrue(output.label.contains("Resting heart rate") || (output.value as? String) == "Resting heart rate")
        XCTAssertTrue(inputs.label.contains("Caffeine") || (inputs.value as? String)?.contains("Caffeine") == true)

        let behaviorWindow = app.descendants(matching: .any)["explore.behaviorWindow"].firstMatch
        let history = app.descendants(matching: .any)["explore.history"].firstMatch
        behaviorWindow.tap()
        let week = app.descendants(matching: .any)["Complete preceding 7 days"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Complete preceding 30 days"].firstMatch.exists)
        week.tap()
        history.tap()
        let recentHistory = app.descendants(matching: .any)["Last 90 days"].firstMatch
        XCTAssertTrue(recentHistory.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Last 365 days"].firstMatch.exists)
        recentHistory.tap()
        for _ in 0..<3 where !analyze.isHittable { app.swipeUp() }
        analyze.tap()
        XCTAssertTrue(app.navigationBars["Analysis result"].waitForExistence(timeout: 5))
        let windowResult = app.descendants(matching: .any)["explore.result.behaviorWindow"].firstMatch
        let historyResult = app.descendants(matching: .any)["explore.result.history"].firstMatch
        for _ in 0..<5 where !historyResult.isHittable { app.swipeUp() }
        XCTAssertTrue(windowResult.label.contains("Complete preceding 7 days")
            || (windowResult.value as? String) == "Complete preceding 7 days")
        XCTAssertTrue(historyResult.label.contains("Last 90 days") || (historyResult.value as? String) == "Last 90 days")
        app.navigationBars["Analysis result"].buttons.firstMatch.tap()
        XCTAssertTrue(behaviorWindow.label.contains("Complete preceding 7 days")
            || (behaviorWindow.value as? String) == "Complete preceding 7 days")
        XCTAssertTrue(history.label.contains("Last 90 days") || (history.value as? String) == "Last 90 days")
    }
}
