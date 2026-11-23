import XCTest

final class BinaryAnalysisUITests: XCTestCase {
    @MainActor
    func testBuildsAdjustedYesNoQuestionAndInspectsPairedProvenance() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_BINARY_UI_FIXTURE"] = "1"
        app.launch()

        app.tabBars.buttons["Explore"].tap()
        let output = app.descendants(matching: .any)["explore.output"].firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        output.tap()
        let headache = app.descendants(matching: .any)["Headache (yes/no)"].firstMatch
        XCTAssertTrue(headache.waitForExistence(timeout: 5))
        headache.tap()

        app.descendants(matching: .any)["explore.inputs"].firstMatch.tap()
        let meal = app.switches["Late meal (yes/no)"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.tapExploreSwitch()
        XCTAssertFalse(app.switches["Headache (yes/no)"].exists)
        app.navigationBars["Inputs"].buttons.firstMatch.tap()

        app.descendants(matching: .any)["explore.adjustments"].firstMatch.tap()
        let shift = app.switches["Night shift (yes/no)"]
        XCTAssertTrue(shift.waitForExistence(timeout: 5))
        shift.tapExploreSwitch()
        app.navigationBars["Account for"].buttons.firstMatch.tap()
        let limitation = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Interactions with yes/no variables are unavailable.")
        ).firstMatch
        for _ in 0..<3 where !limitation.isHittable { app.swipeUp() }
        XCTAssertTrue(limitation.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["explore.interaction"].firstMatch.exists)

        let analyze = app.buttons["Analyze"]
        for _ in 0..<4 where !analyze.isHittable { app.swipeUp() }
        XCTAssertTrue(analyze.isHittable)
        analyze.tap()
        let effect = app.staticTexts.matching(identifier: "explore.binaryEffect").firstMatch
        XCTAssertTrue(effect.waitForExistence(timeout: 5))
        XCTAssertTrue(effect.label.contains("40 percentage points"))
        XCTAssertTrue(effect.label.contains("Yes versus No"))
        XCTAssertTrue(app.descendants(matching: .any)["explore.uncertainty"].firstMatch.exists)

        let coverage = app.buttons["Usable dates and gaps"]
        for _ in 0..<6 where !coverage.isHittable { app.swipeUp() }
        XCTAssertTrue(coverage.isHittable)
        coverage.tap()
        XCTAssertTrue(app.navigationBars["Usable dates and gaps"].waitForExistence(timeout: 5))
        let firstPair = app.buttons.matching(identifier: "explore.pairedYesNo").firstMatch
        for _ in 0..<6 where !firstPair.isHittable { app.swipeUp() }
        XCTAssertTrue(firstPair.isHittable)
        firstPair.tap()
        XCTAssertTrue(app.navigationBars["Paired values"].waitForExistence(timeout: 5))
        let outputValue = app.descendants(matching: .any).matching(identifier: "explore.pairedValue")
            .matching(NSPredicate(format: "label == %@", "Headache")).firstMatch
        XCTAssertEqual(outputValue.value as? String, "No")
        XCTAssertTrue(app.staticTexts["Explicit observation"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Assumed default effective")).firstMatch.exists)
        app.navigationBars["Paired values"].buttons.firstMatch.tap()
        app.navigationBars["Usable dates and gaps"].buttons.firstMatch.tap()

        let model = app.buttons["Model and evidence"]
        for _ in 0..<10 where !model.isHittable { app.swipeUp() }
        XCTAssertTrue(model.isHittable)
        model.tap()
        XCTAssertTrue(app.navigationBars["Model and evidence"].waitForExistence(timeout: 5))
        let modeledShift = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Night shift (yes/no)")).firstMatch
        for _ in 0..<3 where !modeledShift.isHittable { app.swipeUp() }
        XCTAssertTrue(modeledShift.label.contains("Adjustment input"))
    }
}
