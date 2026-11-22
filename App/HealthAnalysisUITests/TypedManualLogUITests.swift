import XCTest

final class TypedManualLogUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testConfigureAndRevisitTypedFieldsOnTheSelectedDay() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HEALTH_ANALYSIS_MANUAL_LOG_TEST_STORE"] = UUID().uuidString
        app.launch()

        app.buttons["Settings"].tap()

        openCreation("Add count", named: "Alcohol servings", in: app)
        let defaultCount = app.textFields["Default count"]
        defaultCount.tap()
        defaultCount.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(app.staticTexts["Enter a whole number of zero or more."].exists)
        XCTAssertFalse(app.navigationBars["New count"].buttons["Add"].isEnabled)
        defaultCount.typeText("2")
        saveCreation("New count", in: app)

        openCreation("Add yes/no", named: "Took medication", in: app)
        XCTAssertTrue(app.switches["Default value"].exists)
        saveCreation("New yes/no", in: app)

        openCreation("Add rating", named: "Energy", in: app)
        XCTAssertEqual(app.textFields["Default rating"].value as? String, "3")
        saveCreation("New rating", in: app)

        openCreation("Add category", named: "Workout location", in: app)
        let first = app.textFields["Category 1"]
        first.tap()
        first.typeText("Indoors")
        let second = app.textFields["Category 2"]
        second.tap()
        second.typeText("Outdoors")
        saveCreation("New category", in: app)

        app.navigationBars["Settings"].buttons["Close"].tap()
        app.buttons["Log"].tap()
        let servings = named("Alcohol servings", in: app.steppers)
        let energy = named("Energy", in: app.steppers)
        XCTAssertTrue(servings.waitForExistence(timeout: 5))
        assertValues(count: "2", medication: "0", rating: "3", location: "Indoors", in: app)

        app.buttons["Previous day"].tap()
        servings.buttons["Decrement"].tap()
        let medication = app.switches["Took medication"]
        let switchControl = medication.switches.firstMatch
        (switchControl.exists ? switchControl : medication).tap()
        energy.buttons["Increment"].tap()
        let location = named("Workout location", in: app.buttons)
        location.tap()
        XCTAssertFalse(app.buttons["Unknown"].exists)
        XCTAssertFalse(app.staticTexts["Unknown"].exists)
        app.buttons["Outdoors"].tap()
        assertValues(count: "1", medication: "1", rating: "4", location: "Outdoors", in: app)

        let confirm = app.buttons["Confirm day"]
        for _ in 0..<3 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.isHittable)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Day reviewed"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        app.buttons["Log"].tap()
        XCTAssertTrue(servings.waitForExistence(timeout: 5))
        assertValues(count: "2", medication: "0", rating: "3", location: "Indoors", in: app)
        app.buttons["Previous day"].tap()
        assertValues(count: "1", medication: "1", rating: "4", location: "Outdoors", in: app)
    }

    @MainActor
    private func openCreation(_ action: String, named name: String, in app: XCUIApplication) {
        let button = app.buttons[action]
        for _ in 0..<3 where !button.isHittable {
            app.swipeUp()
        }
        button.tap()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
        app.buttons["Previous day"].tap()
        let field = app.textFields["Name"]
        field.tap()
        field.typeText(name)
    }

    @MainActor
    private func saveCreation(_ title: String, in app: XCUIApplication) {
        app.navigationBars[title].buttons["Add"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertValues(count: String, medication: String, rating: String, location: String, in app: XCUIApplication) {
        XCTAssertEqual(named("Alcohol servings", in: app.steppers).value as? String, count)
        XCTAssertEqual(app.switches["Took medication"].value as? String, medication)
        XCTAssertEqual(named("Energy", in: app.steppers).value as? String, rating)
        XCTAssertEqual(named("Workout location", in: app.buttons).value as? String, location)
    }

    @MainActor
    private func named(_ label: String, in query: XCUIElementQuery) -> XCUIElement {
        query.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, "\(label), ")).firstMatch
    }
}
