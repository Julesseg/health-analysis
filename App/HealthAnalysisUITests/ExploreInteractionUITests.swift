import XCTest

final class ExploreInteractionUITests: XCTestCase {
    @MainActor
    func testComparesLabeledConditionsAfterSelectingThreeInputs() {
        let app = analyzeInteraction(fixture: "planted")
        let finding = app.staticTexts["The estimated association is more positive at the higher condition."]
        XCTAssertTrue(finding.waitForExistence(timeout: 5))
        let lower = app.descendants(matching: .any)["explore.interaction.lower"].firstMatch
        let higher = app.descendants(matching: .any)["explore.interaction.higher"].firstMatch
        XCTAssertTrue(reveal(lower, in: app))
        XCTAssertTrue(lower.label.contains("1 L"))
        XCTAssertTrue(lower.label.contains("2 bpm"))
        XCTAssertTrue(reveal(higher, in: app))
        XCTAssertTrue(higher.label.contains("3 L"))
        XCTAssertTrue(higher.label.contains("8 bpm"))
        XCTAssertTrue(reveal(app.descendants(matching: .any)["explore.interaction.uncertainty"].firstMatch, in: app))
        XCTAssertTrue(reveal(app.staticTexts["With Fluids at 2 L."], in: app))

        app.navigationBars["Analysis result"].buttons.firstMatch.tap()
        let interaction = app.descendants(matching: .any)["explore.interaction"].firstMatch
        for _ in 0..<3 where !interaction.isHittable { app.swipeDown() }
        XCTAssertTrue(interaction.isHittable)
        XCTAssertTrue(interaction.label.contains("Caffeine") || (interaction.value as? String)?.contains("Caffeine") == true)
    }

    @MainActor
    func testShowsAnEstimatedNearZeroInteraction() {
        let app = analyzeInteraction(fixture: "null")
        XCTAssertTrue(app.staticTexts["The estimated associations are similar across these conditions."]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(reveal(app.descendants(matching: .any)["explore.interaction.uncertainty"].firstMatch, in: app))
    }

    @MainActor
    func testExplainsCollinearInputs() {
        let app = analyzeInteraction(fixture: "collinear")
        XCTAssertTrue(app.staticTexts["There isn’t enough evidence to compare these conditions."]
            .waitForExistence(timeout: 5))
        let reason = app.staticTexts["These inputs vary together too closely to estimate their separate associations."]
        XCTAssertTrue(reveal(reason, in: app))
    }

    @MainActor
    func testExplainsPoorlyRepresentedCombinations() {
        let app = analyzeInteraction(fixture: "sparse")
        XCTAssertTrue(app.staticTexts["There isn’t enough evidence to compare these conditions."]
            .waitForExistence(timeout: 5))
        let reason = app.staticTexts["Too few jointly recorded days support the lower and higher combinations."]
        XCTAssertTrue(reveal(reason, in: app))
    }

    @MainActor
    private func analyzeInteraction(fixture: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_INTERACTION_UI_FIXTURE"] = fixture
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

        let interaction = app.descendants(matching: .any)["explore.interaction"].firstMatch
        XCTAssertTrue(reveal(interaction, in: app))
        interaction.tap()
        let focal = app.descendants(matching: .any)["explore.interaction.focal"].firstMatch
        XCTAssertTrue(focal.waitForExistence(timeout: 5))
        focal.tap()
        app.descendants(matching: .any)["Caffeine"].firstMatch.tap()
        let moderator = app.descendants(matching: .any)["explore.interaction.moderator"].firstMatch
        XCTAssertTrue(moderator.waitForExistence(timeout: 5))
        XCTAssertTrue(moderator.label.contains("Fluids") || (moderator.value as? String)?.contains("Fluids") == true)
        app.navigationBars["Interaction"].buttons.firstMatch.tap()

        let analyze = app.buttons["Analyze"]
        XCTAssertTrue(reveal(analyze, in: app))
        analyze.tap()
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<7 where !element.isHittable { app.swipeUp() }
        return element.isHittable
    }
}
