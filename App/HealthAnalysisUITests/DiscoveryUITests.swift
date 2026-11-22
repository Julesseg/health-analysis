import XCTest

final class DiscoveryUITests: XCTestCase {
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
    func testSavedDiscoveryShowsReversingSupportAndSeparateEvidenceDates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_DISCOVERY_REASSESSMENT_UI_FIXTURE"] = "1"
        app.launch()

        let saved = app.buttons["savedAnalysis.open"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 15))
        saved.tap()
        XCTAssertTrue(app.staticTexts["Subsequent-data support is unassessed."].waitForExistence(timeout: 5))
        let refresh = app.buttons["analysis.refresh"]
        for _ in 0..<8 where !refresh.isHittable { app.swipeUp() }
        XCTAssertTrue(refresh.isHittable)
        refresh.tap()

        let support = app.staticTexts["discovery.laterSupport"]
        for _ in 0..<8 where !support.isHittable { app.swipeDown() }
        XCTAssertTrue(support.waitForExistence(timeout: 10))
        XCTAssertEqual(support.label, "Later evidence points in the opposite direction.")
        app.buttons["discovery.evidence"].tap()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let cutoff = calendar.date(byAdding: .day, value: -80, to: today)!
        let paired = calendar.date(byAdding: .day, value: -2, to: today)!
        let head = calendar.date(byAdding: .day, value: -1, to: today)!
        var format = Date.FormatStyle.dateTime.year().month(.abbreviated).day().locale(Locale(identifier: "en_US"))
        format.timeZone = calendar.timeZone

        let originalDate = app.descendants(matching: .any)["discovery.original.latestPairedOutput"].firstMatch
        XCTAssertTrue(originalDate.waitForExistence(timeout: 5))
        XCTAssertTrue(showsSelection(cutoff.formatted(format), in: originalDate))

        let latestEligible = app.descendants(matching: .any)["discovery.latestEligibleOutput"].firstMatch
        for _ in 0..<8 where !latestEligible.isHittable { app.swipeUp() }
        XCTAssertTrue(latestEligible.isHittable)
        XCTAssertTrue(showsSelection(head.formatted(format), in: latestEligible))
        let latestPaired = app.descendants(matching: .any)["discovery.later.latestPairedOutput"].firstMatch
        for _ in 0..<8 where !latestPaired.isHittable { app.swipeUp() }
        XCTAssertTrue(latestPaired.isHittable)
        XCTAssertTrue(showsSelection(paired.formatted(format), in: latestPaired))
    }

    @MainActor
    private func showsSelection(_ title: String, in element: XCUIElement) -> Bool {
        element.label.contains(title) || (element.value as? String)?.contains(title) == true
    }
}
