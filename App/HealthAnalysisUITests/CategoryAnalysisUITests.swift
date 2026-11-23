import XCTest

final class CategoryAnalysisUITests: XCTestCase {
    @MainActor
    func testSelectsCategoryRolesAndInspectsNamedOddsAndRecordedValues() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_CATEGORY_UI_FIXTURE"] = "1"
        app.launch()

        app.tabBars.buttons["Explore"].tap()
        choose("Headache type (category)", in: "explore.output", app: app)
        choose("Migraine", in: "explore.category.event", app: app)

        app.descendants(matching: .any)["explore.inputs"].firstMatch.tap()
        let setting = app.switches["Work setting (category)"]
        XCTAssertTrue(setting.waitForExistence(timeout: 5))
        setting.tapExploreSwitch()
        XCTAssertFalse(app.switches["Headache type (category)"].exists)
        app.navigationBars["Inputs"].buttons.firstMatch.tap()

        let analyze = app.buttons["Analyze"]
        choose("Home", in: "explore.category.reference", app: app)
        choose("Office", in: "explore.category.comparison", app: app)
        for _ in 0..<5 where !analyze.isHittable { app.swipeUp() }
        XCTAssertTrue(analyze.isEnabled)
        analyze.tap()

        let effect = app.staticTexts["explore.category.effect"]
        XCTAssertTrue(effect.waitForExistence(timeout: 5))
        XCTAssertTrue(effect.label.contains("odds of Migraine"))
        XCTAssertTrue(effect.label.contains("Office compared with Home"))
        XCTAssertTrue(app.descendants(matching: .any)["explore.uncertainty"].firstMatch.exists)

        let model = app.buttons["Model and evidence"]
        for _ in 0..<12 where !model.isHittable { app.swipeUp() }
        XCTAssertTrue(model.isHittable)
        model.tap()
        XCTAssertTrue(app.navigationBars["Model and evidence"].waitForExistence(timeout: 5))
        let input = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Work setting")).firstMatch
        for _ in 0..<6 where !input.isHittable { app.swipeUp() }
        XCTAssertTrue(input.isHittable)
        input.tap()

        let recordedPair = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Home and Migraine")).firstMatch
        for _ in 0..<6 where !recordedPair.isHittable { app.swipeUp() }
        XCTAssertTrue(recordedPair.isHittable)
        recordedPair.tap()
        XCTAssertTrue(app.navigationBars["Paired values"].waitForExistence(timeout: 5))
        let provenance = app.descendants(matching: .any)["explore.inputProvenance"].firstMatch
        for _ in 0..<3 where !provenance.isHittable { app.swipeUp() }
        XCTAssertTrue(provenance.isHittable)
        XCTAssertEqual(provenance.value as? String, "Explicit observation")
    }

    @MainActor
    private func choose(_ option: String, in identifier: String, app: XCUIApplication) {
        let picker = app.descendants(matching: .any)[identifier].firstMatch
        for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        let choice = app.descendants(matching: .any)[option].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
    }
}
