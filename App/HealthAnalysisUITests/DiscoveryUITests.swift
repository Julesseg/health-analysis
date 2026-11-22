import XCTest

final class DiscoveryUITests: XCTestCase {
    @MainActor
    func testForegroundHealthCheckRefreshesFollowedAnalysisAndDiscoveryAfterUnlock() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_DISCOVERY_UI_FIXTURE"] = "foreground-refresh"
        app.launch()

        let discovery = app.buttons["discovery.open"].firstMatch
        let followed = app.buttons["savedAnalysis.open"].firstMatch
        XCTAssertTrue(discovery.waitForExistence(timeout: 10))
        followed.tap()
        XCTAssertTrue(app.staticTexts["Higher values were associated with higher resting heart rate."]
            .waitForExistence(timeout: 5))
        app.navigationBars["Analysis result"].buttons.firstMatch.tap()

        XCUIDevice.shared.press(.home)
        app.activate()
        let unavailable = app.staticTexts["discovery.unavailable"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10))
        XCTAssertEqual(unavailable.label, "Health data is protected. Unlock your iPhone and try again.")
        XCTAssertTrue(discovery.exists)

        XCUIDevice.shared.press(.home)
        app.activate()
        let empty = app.staticTexts["discovery.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertEqual(empty.label, "There are no readable outputs for discovery.")
        XCTAssertFalse(unavailable.exists)
        followed.tap()
        XCTAssertTrue(app.staticTexts["There isn’t enough evidence to estimate this association."]
            .waitForExistence(timeout: 5))
    }

    @MainActor
    func testFindsOpensEditsAndPinsTheTestedQuestion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_DISCOVERY_UI_FIXTURE"] = "1"
        app.launch()

        let empty = app.staticTexts["discovery.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertEqual(empty.label, "There are no readable outputs for discovery.")
        XCTAssertTrue(app.staticTexts["Discovered for you"].exists)

        app.tabBars.buttons["Data"].tap()
        app.buttons["Resting heart rate"].firstMatch.tap()
        app.buttons["Refresh Health measurements"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["health.lastSuccessfulCheck"].firstMatch.waitForExistence(timeout: 10))

        app.tabBars.buttons["Insights"].tap()
        let discovery = app.buttons["discovery.open"].firstMatch
        XCTAssertTrue(discovery.waitForExistence(timeout: 10))
        discovery.tap()
        XCTAssertTrue(app.staticTexts["Selected in an exploratory search"].waitForExistence(timeout: 5))

        let edit = app.buttons["Edit analysis"]
        for _ in 0..<5 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        let window = app.descendants(matching: .any)["explore.behaviorWindow"].firstMatch
        let history = app.descendants(matching: .any)["explore.history"].firstMatch
        XCTAssertTrue(showsSelection("Complete preceding day", in: window))
        XCTAssertTrue(showsSelection("Last 365 days", in: history))
        let output = app.descendants(matching: .any)["explore.output"].firstMatch
        XCTAssertTrue(showsSelection("Discovery fixture watch", in: output))
        app.descendants(matching: .any)["explore.inputs"].firstMatch.tap()
        XCTAssertEqual(app.switches["Caffeine (mg)"].value as? String, "1")
        app.navigationBars["Inputs"].buttons.firstMatch.tap()

        let analyze = app.buttons["Analyze"]
        for _ in 0..<3 where !analyze.isHittable { app.swipeUp() }
        XCTAssertTrue(analyze.isHittable)
        analyze.tap()
        XCTAssertTrue(app.staticTexts["Selected in an exploratory search"].waitForExistence(timeout: 5))
        app.buttons["analysis.save"].tap()
        let pin = app.buttons["analysis.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        XCTAssertTrue(app.buttons["analysis.unpin"].waitForExistence(timeout: 5))

        app.navigationBars["Analysis result"].buttons.firstMatch.tap()
        app.navigationBars["Edit analysis"].buttons.firstMatch.tap()
        app.navigationBars["Analysis result"].buttons.firstMatch.tap()
        let followed = app.buttons["savedAnalysis.open"].firstMatch
        XCTAssertTrue(followed.waitForExistence(timeout: 5))
        followed.tap()
        XCTAssertTrue(app.staticTexts["Selected in an exploratory search"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func showsSelection(_ title: String, in element: XCUIElement) -> Bool {
        element.label.contains(title) || (element.value as? String)?.contains(title) == true
    }
}
