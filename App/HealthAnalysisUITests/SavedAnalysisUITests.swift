import XCTest

final class SavedAnalysisUITests: XCTestCase {
    @MainActor
    func testSavesPinsAndEditsAQuestionThroughInsightsAndExplore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_EXPLORE_UI_FIXTURE"] = "1"
        app.launchEnvironment["HEALTH_ANALYSIS_SAVED_ANALYSIS_UI_FIXTURE"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["No followed analyses yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No discoveries yet"].exists)
        XCTAssertTrue(app.staticTexts["No readable measurements"].exists)
        XCTAssertLessThan(app.staticTexts["Following"].frame.minY, app.staticTexts["Discovered for you"].frame.minY)
        XCTAssertLessThan(app.staticTexts["Discovered for you"].frame.minY, app.staticTexts["Latest measurements"].frame.minY)

        app.tabBars.buttons["Explore"].tap()
        app.descendants(matching: .any)["explore.output"].firstMatch.tap()
        app.descendants(matching: .any)["Resting heart rate"].firstMatch.tap()
        app.descendants(matching: .any)["explore.inputs"].firstMatch.tap()
        let caffeine = app.switches["Caffeine (mg)"]
        let fluids = app.switches["Fluids (L)"]
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5))
        caffeine.tapExploreSwitch()
        fluids.tapExploreSwitch()
        app.navigationBars["Inputs"].buttons.firstMatch.tap()
        let accountFor = app.descendants(matching: .any)["explore.adjustments"].firstMatch
        accountFor.tap()
        let supplement = app.switches["Supplement (mg)"]
        XCTAssertTrue(supplement.waitForExistence(timeout: 5))
        supplement.tapExploreSwitch()
        app.navigationBars["Account for"].buttons.firstMatch.tap()

        let save = app.buttons["analysis.save"]
        let analyze = app.buttons["Analyze"]
        for _ in 0..<3 where !analyze.isHittable { app.swipeUp() }
        analyze.tap()
        XCTAssertTrue(app.staticTexts["Higher values were associated with higher resting heart rate."].firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let pin = app.buttons["analysis.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        XCTAssertTrue(app.buttons["analysis.unpin"].waitForExistence(timeout: 5))
        app.navigationBars["Analysis result"].buttons.firstMatch.tap()

        app.tabBars.buttons["Insights"].tap()
        let question = app.buttons["savedAnalysis.open"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.tap()
        XCTAssertTrue(app.staticTexts["Higher values were associated with higher resting heart rate."].firstMatch
            .waitForExistence(timeout: 5))
        let edit = app.buttons["Edit analysis"]
        for _ in 0..<8 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        let inputs = app.descendants(matching: .any)["explore.inputs"].firstMatch
        XCTAssertTrue(inputs.label.contains("2 selected") || (inputs.value as? String) == "2 selected")
        accountFor.tap()
        XCTAssertEqual(supplement.value as? String, "1")
        app.navigationBars["Account for"].buttons.firstMatch.tap()
        inputs.tap()
        XCTAssertEqual(caffeine.value as? String, "1")
        XCTAssertEqual(fluids.value as? String, "1")
        caffeine.tapExploreSwitch()
        app.switches["Evening caffeine (mg)"].tapExploreSwitch()
        app.navigationBars["Inputs"].buttons.firstMatch.tap()
        for _ in 0..<3 where !analyze.isHittable { app.swipeUp() }
        analyze.tap()
        XCTAssertTrue(app.staticTexts["There isn’t enough evidence to estimate this association."]
            .waitForExistence(timeout: 5))
        app.buttons["analysis.update"].tap()
        XCTAssertTrue(app.buttons["analysis.unpin"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Explore"].tap()
        for _ in 0..<3 where !question.isHittable { app.swipeUp() }
        XCTAssertTrue(question.isHittable)
        question.tap()
        XCTAssertTrue(app.staticTexts["There isn’t enough evidence to estimate this association."]
            .waitForExistence(timeout: 5))
    }
}
