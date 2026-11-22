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
        let caffeine = app.switches["Caffeine (mg)"]
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5))
        caffeine.tapExploreSwitch()
        app.navigationBars["Inputs"].buttons.firstMatch.tap()

        let analyze = app.buttons["Analyze"]
        for _ in 0..<3 where !analyze.isHittable { app.swipeUp() }
        analyze.tap()
        XCTAssertTrue(app.staticTexts["Higher values were associated with higher resting heart rate."]
            .waitForExistence(timeout: 5))
        let interval = app.descendants(matching: .any)["explore.uncertainty"].firstMatch
        XCTAssertTrue(interval.exists)
        let chart = app.descendants(matching: .any)["explore.estimateChart"].firstMatch
        for _ in 0..<3 where !chart.isHittable { app.swipeUp() }
        XCTAssertTrue(chart.isHittable)
        XCTAssertEqual(chart.label, "Association estimate and uncertainty for Caffeine")
        XCTAssertTrue((chart.value as? String)?.contains("Higher values were associated") == true)
        let observed = app.buttons["Observed measurements"]
        for _ in 0..<6 where !observed.isHittable { app.swipeUp() }
        XCTAssertTrue(observed.isHittable)
        observed.tap()
        let timeline = app.descendants(matching: .any)["explore.observedTimeline"].firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        XCTAssertEqual(timeline.label, "Observed timeline for Resting heart rate")
        XCTAssertTrue((timeline.value as? String)?.contains("113") == true)
        let scatter = app.descendants(matching: .any)["explore.observedScatter"].firstMatch
        for _ in 0..<3 where !scatter.isHittable { app.swipeUp() }
        XCTAssertTrue(scatter.isHittable)
        XCTAssertEqual(scatter.label, "Observed scatterplot for Caffeine and Resting heart rate")
        XCTAssertTrue((scatter.value as? String)?.contains("112") == true)
        XCTAssertFalse(chart.exists)
        app.navigationBars["Observed measurements"].buttons.firstMatch.tap()

        let coverage = app.buttons["Usable dates and gaps"]
        for _ in 0..<4 where !coverage.isHittable { app.swipeUp() }
        XCTAssertTrue(coverage.isHittable)
        coverage.tap()
        XCTAssertTrue(app.navigationBars["Usable dates and gaps"].waitForExistence(timeout: 5))
        let source = app.descendants(matching: .any)["explore.outputSource"].firstMatch
        for _ in 0..<3 where !source.isHittable { app.swipeUp() }
        XCTAssertEqual(source.value as? String, "fixture.explore")
        let missing = app.buttons["Inspect missing input dates"]
        for _ in 0..<5 where !missing.isHittable { app.swipeUp() }
        missing.tap()
        XCTAssertTrue(app.navigationBars["Missing input dates"].waitForExistence(timeout: 5))
        let missingCaffeine = app.descendants(matching: .any)["explore.missingInput"].firstMatch
        XCTAssertTrue(missingCaffeine.isHittable)
        XCTAssertTrue(missingCaffeine.label.contains("Caffeine"))
        missingCaffeine.tap()
        XCTAssertTrue(app.staticTexts["No tracking variables for this date"].waitForExistence(timeout: 5))
        app.navigationBars["Log"].buttons.firstMatch.tap()
        app.navigationBars["Missing input dates"].buttons.firstMatch.tap()
        app.navigationBars["Usable dates and gaps"].buttons.firstMatch.tap()
        app.navigationBars["Analysis result"].buttons.firstMatch.tap()
        XCTAssertTrue(analyze.isEnabled)
        XCTAssertTrue(output.label.contains("Resting heart rate") || (output.value as? String) == "Resting heart rate")
        XCTAssertTrue(inputs.label.contains("Caffeine") || (inputs.value as? String)?.contains("Caffeine") == true)
    }

    @MainActor
    func testBuildsJointAnalysisAndChangesTheAdjustment() {
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
        app.descendants(matching: .any)["explore.output"].firstMatch.tap()
        app.descendants(matching: .any)["Resting heart rate"].firstMatch.tap()
        app.descendants(matching: .any)["explore.inputs"].firstMatch.tap()
        for label in ["Caffeine (mg)", "Fluids (L)", "Exercise log (min)"] {
            let choice = app.switches[label]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tapExploreSwitch()
        }
        app.navigationBars["Inputs"].buttons.firstMatch.tap()

        let accountFor = app.descendants(matching: .any)["explore.adjustments"].firstMatch
        accountFor.tap()
        let supplement = app.switches["Supplement (mg)"]
        XCTAssertTrue(supplement.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Caffeine (mg)"].exists)
        supplement.tapExploreSwitch()
        app.navigationBars["Account for"].buttons.firstMatch.tap()

        let analyze = app.buttons["Analyze"]
        for _ in 0..<3 where !analyze.isHittable { app.swipeUp() }
        analyze.tap()
        XCTAssertTrue(app.descendants(matching: .any)["explore.uncertainty"].firstMatch.waitForExistence(timeout: 5))
        let adjustmentEstimate = app.staticTexts["Account for · Supplement"]
        for _ in 0..<8 where !adjustmentEstimate.isHittable { app.swipeUp() }
        XCTAssertTrue(adjustmentEstimate.isHittable)
        let model = app.buttons["Model and evidence"]
        for _ in 0..<5 where !model.isHittable { app.swipeUp() }
        model.tap()
        XCTAssertTrue(app.navigationBars["Model and evidence"].waitForExistence(timeout: 5))
        let modeledSupplement = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Supplement (mg)")).firstMatch
        for _ in 0..<3 where !modeledSupplement.isHittable { app.swipeUp() }
        XCTAssertTrue(modeledSupplement.label.contains("Adjustment input"))
        modeledSupplement.tap()
        XCTAssertTrue(app.navigationBars["Supplement"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Explicit observations"].exists)
        app.navigationBars["Supplement"].buttons.firstMatch.tap()
        app.navigationBars["Model and evidence"].buttons.firstMatch.tap()
        app.navigationBars["Analysis result"].buttons.firstMatch.tap()

        for _ in 0..<3 where !accountFor.isHittable { app.swipeDown() }
        accountFor.tap()
        XCTAssertEqual(supplement.value as? String, "1")
        supplement.tapExploreSwitch()
        app.navigationBars["Account for"].buttons.firstMatch.tap()
        XCTAssertTrue(accountFor.label.contains("None") || (accountFor.value as? String)?.contains("None") == true)
    }
}

extension XCUIElement {
    @MainActor
    func tapExploreSwitch() {
        let control = switches.firstMatch
        (control.exists ? control : self).tap()
    }
}
