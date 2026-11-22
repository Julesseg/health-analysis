import XCTest

final class HealthMeasurementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRequestShowsLoadingWhileHealthIsReading() {
        let app = launch(fixture: "loading")
        openAccessAndSources(in: app)

        app.buttons["Request read access"].tap()

        let progress = app.descendants(matching: .any)["health.readProgress"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
    }

    @MainActor
    func testEmptyReadOffersAccessAndSourceReview() {
        let app = launch(fixture: "empty")
        openAccessAndSources(in: app)
        XCTAssertTrue(app.staticTexts["Health Analysis reads resting heart rate to show your measurements over time."].exists)

        app.buttons["Request read access"].tap()

        XCTAssertTrue(app.staticTexts["No readable measurements"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No imported sources"].exists)
        XCTAssertTrue(app.buttons["Request read access"].isEnabled)
    }

    @MainActor
    func testImportedHistoryAndLatestMeasurementSurviveProtectedRead() {
        let app = launch(fixture: "protectedAfterImport")
        openAccessAndSources(in: app)
        app.buttons["Request read access"].tap()
        XCTAssertTrue(app.staticTexts["fixture.livity"].waitForExistence(timeout: 5))

        app.navigationBars.buttons["Data"].tap()
        app.buttons["Resting heart rate"].tap()
        XCTAssertTrue(app.staticTexts["62 beats per minute"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["58 beats per minute"].exists)

        app.buttons["Refresh Health measurements"].tap()

        XCTAssertTrue(app.staticTexts["Health data is protected. Unlock your iPhone and try again."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["62 beats per minute"].exists)

        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["Latest measurements"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["62 beats per minute"].exists)
        XCTAssertFalse(app.staticTexts["58 beats per minute"].exists)
    }

    @MainActor
    private func launch(fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_MEASUREMENT_UI_FIXTURE"] = fixture
        app.launch()
        return app
    }

    @MainActor
    private func openAccessAndSources(in app: XCUIApplication) {
        app.tabBars.buttons["Data"].tap()
        app.buttons["Health access and sources"].tap()
        XCTAssertTrue(app.buttons["Request read access"].waitForExistence(timeout: 5))
    }
}
