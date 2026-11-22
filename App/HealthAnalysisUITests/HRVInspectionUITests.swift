import XCTest

final class HRVInspectionUITests: XCTestCase {
    @MainActor
    func testHistorySeparatesStoredTypesAndExplainsAnalysisLimit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_MEASUREMENT_UI_FIXTURE"] = "hrv"
        app.launchEnvironment["HEALTH_MEASUREMENT_UI_FIXTURE_STORE"] = UUID().uuidString
        app.launch()

        app.tabBars.buttons["Data"].tap()
        app.buttons["Health access and sources"].tap()
        app.buttons["Request read access"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "fixture.livity").firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["Data"].tap()
        app.buttons["Heart rate variability"].tap()

        let sdnn = app.buttons["hrv.series.HKQuantityTypeIdentifierHeartRateVariabilitySDNN.fixture.livity"]
        let rmssd = app.buttons["hrv.series.HKQuantityTypeIdentifierHeartRateVariabilityRMSSD.fixture.livity"]
        XCTAssertTrue(sdnn.waitForExistence(timeout: 5))
        XCTAssertTrue(rmssd.exists)

        sdnn.tap()
        XCTAssertTrue(app.staticTexts["Stored in HealthKit as SDNN"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Analysis unavailable until the original HRV measure and how it was summarized are verified."].exists)
        let missingDays = app.descendants(matching: .any)["hrv.coverage.daysWithoutMeasurements"].firstMatch
        for _ in 0..<3 where !missingDays.isHittable { app.swipeUp() }
        XCTAssertTrue(missingDays.isHittable)
        XCTAssertEqual(missingDays.value as? String, "1")
        let record = app.buttons["hrv.record.92E81B9E-55ED-46E7-9C33-B0EB6DDFC001"]
        for _ in 0..<3 where !record.isHittable { app.swipeUp() }
        XCTAssertTrue(record.isHittable)
        record.tap()

        XCTAssertTrue(app.staticTexts["42 milliseconds"].waitForExistence(timeout: 5))
        let sourceVersion = app.staticTexts["1.2"]
        for _ in 0..<3 where !sourceVersion.isHittable { app.swipeUp() }
        XCTAssertTrue(sourceVersion.isHittable)
    }
}
