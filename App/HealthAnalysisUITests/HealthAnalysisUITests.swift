import XCTest

final class HealthAnalysisUITests: XCTestCase {
    @MainActor
    func testAnalysisNavigationAndDailyQuantityLog() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_UI_TEST_STORE"] = UUID().uuidString
        app.launch()

        let tabs = app.tabBars
        XCTAssertTrue(tabs.buttons["Analysis"].isSelected)
        XCTAssertEqual(tabs.buttons.count, 2)
        XCTAssertTrue(app.staticTexts["No saved analyses yet."].exists)
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped, .sufficientElementDescription])
        capture("Analysis", app)

        app.buttons["New Analysis"].tap()
        XCTAssertTrue(app.navigationBars["New Analysis"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Inputs"].exists)
        XCTAssertTrue(app.staticTexts["Output"].exists)
        capture("New Analysis", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Discover"].tap()
        XCTAssertTrue(app.navigationBars["Discover"].waitForExistence(timeout: 5))
        capture("Discover", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("Settings", app)
        app.buttons["Done"].tap()
        tabs.buttons["Log"].tap()
        let today = app.buttons["logDay-0"]
        XCTAssertTrue(today.isSelected)
        XCTAssertEqual(today.value as? String, "No saved edits")
        XCTAssertTrue(app.staticTexts["No tracking variables configured."].exists)
        capture("Log", app)

        let dateHeader = app.staticTexts["selectedLogDate"]
        let todayLabel = dateHeader.label
        showPreviousWeek(in: app)
        let earlier = app.buttons["logDay-7"]
        earlier.tap()
        XCTAssertTrue(earlier.isSelected)
        XCTAssertNotEqual(dateHeader.label, todayLabel)

        let categories = app.buttons["Log Categories"]
        categories.tap()
        XCTAssertTrue(app.navigationBars["Log Categories"].waitForExistence(timeout: 5))
        capture("Empty Log Categories", app)
        app.buttons["Add Quantity"].tap()
        XCTAssertTrue(app.navigationBars["New Quantity"].waitForExistence(timeout: 5))
        capture("New Quantity", app)
        let name = app.textFields["quantityName"]
        name.tap()
        name.typeText("Caffeine")
        let unit = app.textFields["quantityUnit"]
        unit.tap()
        unit.typeText("mg")
        let defaultValue = app.textFields["Default value"]
        defaultValue.tap()
        defaultValue.typeText("0")
        app.buttons["Save"].tap()
        let caffeine = categoryButton(labeled: "Caffeine (mg)", in: app)
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5))
        capture("Log Categories", app)
        app.buttons["Done"].tap()

        let field = app.textFields["Caffeine (mg)"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.buttons["logDay-8"].tap()
        XCTAssertTrue(app.staticTexts["No tracking variables for this day."].exists)
        XCTAssertFalse(field.exists)
        earlier.tap()
        XCTAssertTrue(earlier.isSelected)
        XCTAssertEqual(field.placeholderValue, "0")
        XCTAssertEqual(earlier.value as? String, "No saved edits")
        field.tap()
        field.typeText("12.5.")
        XCTAssertTrue(app.staticTexts["Enter a valid number."].exists)
        XCTAssertEqual(field.value as? String, "12.5.")
        field.typeText("\n")
        capture("Invalid Entry", app)
        field.tap()
        let delete = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5)
        field.typeText(delete)
        field.typeText("7.25")
        XCTAssertEqual(field.value as? String, "7.25")
        field.typeText("\n")
        XCTAssertEqual(earlier.value as? String, "Edits saved")
        capture("Backdated Log", app)

        tabs.buttons["Analysis"].tap()
        tabs.buttons["Log"].tap()
        XCTAssertTrue(today.isSelected)
        XCTAssertEqual(field.placeholderValue, "0")
        XCTAssertTrue(app.staticTexts["Default value"].exists)
        XCTAssertEqual(today.value as? String, "No saved edits")
        capture("Assumed Default", app)
        field.tap()
        field.typeText("0")
        XCTAssertEqual(today.value as? String, "Edits saved")
        XCTAssertFalse(app.staticTexts["Default value"].exists)
        field.typeText("\n")
        capture("Explicit Zero", app)

        app.terminate()
        app.launch()
        tabs.buttons["Log"].tap()
        XCTAssertTrue(today.isSelected)
        XCTAssertEqual(field.value as? String, "0")
        XCTAssertEqual(today.value as? String, "Edits saved")
        showPreviousWeek(in: app)
        earlier.tap()
        XCTAssertEqual(field.value as? String, "7.25")
        XCTAssertEqual(earlier.value as? String, "Edits saved")

        categories.tap()
        caffeine.tap()
        XCTAssertTrue(app.navigationBars["Edit Quantity"].waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" intake")
        name.typeText("\n")
        let endDate = app.switches["Set End Date"]
        endDate.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(endDate.value as? String, "1")
        capture("Edit Tracking Period", app)
        app.buttons["Save"].tap()
        let warning = app.alerts["Remove entries after the end date?"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        capture("Confirm End Date", app)
        warning.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Quantity"].exists)
        app.buttons["Save"].tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        warning.buttons["Remove Entries and Save"].tap()
        let archived = categoryButton(labeled: "Caffeine intake (mg)", in: app)
        XCTAssertTrue(archived.waitForExistence(timeout: 5))
        capture("Archived Category", app)
        app.buttons["Done"].tap()
        XCTAssertEqual(app.textFields["Caffeine intake (mg)"].value as? String, "7.25")
        tabs.buttons["Analysis"].tap()
        tabs.buttons["Log"].tap()
        XCTAssertTrue(today.isSelected)
        XCTAssertEqual(today.value as? String, "No saved edits")
        XCTAssertTrue(app.staticTexts["No tracking variables for this day."].exists)
        capture("Day After Tracking End", app)

        categories.tap()
        archived.tap()
        app.buttons["Remove Quantity"].tap()
        let removal = app.alerts["Remove Caffeine intake?"]
        XCTAssertTrue(removal.waitForExistence(timeout: 5))
        capture("Confirm Quantity Removal", app)
        removal.buttons["Remove"].tap()
        XCTAssertTrue(app.staticTexts["No tracking variables"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        showPreviousWeek(in: app)
        earlier.tap()
        XCTAssertEqual(earlier.value as? String, "No saved edits")
    }

    @MainActor
    private func categoryButton(labeled label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    @MainActor
    private func showPreviousWeek(in app: XCUIApplication) {
        let center = CGVector(dx: 0.5, dy: 0.5)
        let start = app.buttons["logDay-5"].coordinate(withNormalizedOffset: center)
        let end = app.buttons["logDay-1"].coordinate(withNormalizedOffset: center)
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    @MainActor
    private func capture(_ screen: String, _ app: XCUIApplication) {
        guard ProcessInfo.processInfo.environment["CAPTURE_SCREENSHOTS"] == "true" else { return }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = screen
        image.lifetime = .keepAlways
        add(image)
    }
}
