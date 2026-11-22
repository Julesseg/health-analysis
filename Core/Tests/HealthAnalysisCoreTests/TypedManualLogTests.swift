import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct TypedManualLogTests {
    @Test func countDefaultsAndBackdatedExplicitZeroSurviveReopening() throws {
        let url = temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(throws: ManualLog.TypedVariableCreationError.invalidDefinition) {
            try log.createTypedVariable(
                name: "Alcohol servings", kind: .count, defaultValue: .count(-1), startsOn: day(19)
            )
        }
        let count = try log.createTypedVariable(
            name: "Alcohol servings", kind: .count, defaultValue: .count(2), startsOn: day(19)
        )
        log.editTypedEntry(count.id, on: day(18), value: .count(1))
        #expect(log.dailyTypedEntries(on: day(18)).isEmpty)
        #expect(log.dailyTypedEntry(count.id, on: day(19))?.value == .count(2))
        #expect(log.dailyTypedEntry(count.id, on: day(19))?.recordedValue == nil)

        log.editTypedEntry(count.id, on: day(19), value: .count(0))
        log.editTypedEntry(count.id, on: day(19), value: .count(-1))
        #expect(log.dailyTypedEntry(count.id, on: day(19))?.status == .invalid)
        #expect(log.dailyTypedEntry(count.id, on: day(19))?.recordedValue == .count(0))

        let reopened = HealthAnalysisApplication(manualLogStoreURL: url)
        #expect(reopened.overview.hasTrackingVariables)
        #expect(reopened.manualLog.typedVariables == [count])
        let backdated = try #require(reopened.manualLog.dailyTypedEntry(count.id, on: day(19)))
        #expect(backdated.day == day(19))
        #expect(backdated.recordedValue == .count(0))
        #expect(backdated.status == .saved)
        let today = try #require(reopened.manualLog.dailyTypedEntry(count.id, on: day(20)))
        #expect(today.recordedValue == nil)
        #expect(today.value == .count(2))
        #expect(today.status == .assumedDefault)
    }

    @Test func yesNoDistinguishesExplicitNoFromAnUntouchedNoDefault() throws {
        let url = temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        let medication = try log.createTypedVariable(
            name: "Took medication", kind: .yesNo, defaultValue: .yesNo(false), startsOn: day(19)
        )
        log.editTypedEntry(medication.id, on: day(19), value: .yesNo(true))
        log.editTypedEntry(medication.id, on: day(20), value: .yesNo(false))

        let reopened = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(reopened.dailyTypedEntry(medication.id, on: day(19))?.recordedValue == .yesNo(true))
        #expect(reopened.dailyTypedEntry(medication.id, on: day(20))?.recordedValue == .yesNo(false))
        #expect(reopened.dailyTypedEntry(medication.id, on: day(21))?.recordedValue == nil)
        #expect(reopened.dailyTypedEntry(medication.id, on: day(21))?.value == .yesNo(false))
        #expect(reopened.dailyTypedEntry(medication.id, on: day(21))?.variable.kind == .yesNo)
    }

    @Test func ratingRetainsItsOrderedScaleAndRejectsOutOfRangeValues() throws {
        let url = temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(throws: ManualLog.TypedVariableCreationError.invalidDefinition) {
            try log.createTypedVariable(
                name: "Energy", kind: .rating(1...5), defaultValue: .rating(0), startsOn: day(19)
            )
        }
        #expect(throws: ManualLog.TypedVariableCreationError.invalidDefinition) {
            try log.createTypedVariable(
                name: "Energy", kind: .rating(3...3), defaultValue: .rating(3), startsOn: day(19)
            )
        }
        let energy = try log.createTypedVariable(
            name: "Energy", kind: .rating(1...5), defaultValue: .rating(3), startsOn: day(19)
        )
        log.editTypedEntry(energy.id, on: day(19), value: .rating(5))
        log.editTypedEntry(energy.id, on: day(19), value: .rating(6))
        let invalid = try #require(log.dailyTypedEntry(energy.id, on: day(19)))
        #expect(invalid.status == .invalid)
        #expect(invalid.value == .rating(5))

        let reopened = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(reopened.typedVariables.map(\.kind) == [.rating(1...5)])
        #expect(reopened.dailyTypedEntry(energy.id, on: day(19))?.recordedValue == .rating(5))
        #expect(reopened.dailyTypedEntry(energy.id, on: day(20))?.value == .rating(3))
    }

    @Test func categoriesRetainNamedIdentitiesAndRejectUnconfiguredChoices() throws {
        let url = temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        let indoors = TrackingCategory(name: "Indoors")
        let outdoors = TrackingCategory(name: "Outdoors")
        let other = TrackingCategory(name: "Other place")
        #expect(throws: ManualLog.TypedVariableCreationError.invalidDefinition) {
            try log.createTypedVariable(
                name: "Workout location", kind: .category([indoors, outdoors]),
                defaultValue: .category(other.id), startsOn: day(19)
            )
        }
        #expect(throws: ManualLog.TypedVariableCreationError.invalidDefinition) {
            try log.createTypedVariable(
                name: "Workout location", kind: .category([indoors, TrackingCategory(name: "indoors")]),
                defaultValue: .category(indoors.id), startsOn: day(19)
            )
        }
        let location = try log.createTypedVariable(
            name: "Workout location", kind: .category([indoors, outdoors]),
            defaultValue: .category(indoors.id), startsOn: day(19)
        )
        log.editTypedEntry(location.id, on: day(19), value: .category(outdoors.id))
        log.editTypedEntry(location.id, on: day(19), value: .category(other.id))
        #expect(log.dailyTypedEntry(location.id, on: day(19))?.status == .invalid)
        log.editTypedEntry(location.id, on: day(19), value: .count(1))
        #expect(log.dailyTypedEntry(location.id, on: day(19))?.status == .invalid)

        let reopened = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(reopened.typedVariables.map(\.kind) == [.category([indoors, outdoors])])
        #expect(reopened.dailyTypedEntry(location.id, on: day(19))?.recordedValue == .category(outdoors.id))
        #expect(reopened.dailyTypedEntry(location.id, on: day(20))?.value == .category(indoors.id))
    }

    @Test func typedAndQuantityChangesCanAlternateInAPreexistingQuantityStore() throws {
        let url = temporaryStore()
        let directory = url.deletingLastPathComponent()
        let files = FileManager.default
        defer { try? files.removeItem(at: directory) }
        try files.createDirectory(at: directory, withIntermediateDirectories: false)

        // Emitted by the quantity-only build at 0b3337f.
        try Data("""
        {
            "quantities": [{
                "id": "B06F45B6-9899-49F8-A4D3-4A4FB6DB7855",
                "name": "Caffeine", "unit": "mg", "defaultValue": 35,
                "startsOn": {"year": 2026, "month": 11, "day": 20}
            }],
            "entries": [
                {"day": {"year": 2026, "month": 11, "day": 20}, "quantityID": "B06F45B6-9899-49F8-A4D3-4A4FB6DB7855"},
                12.5
            ]
        }
        """.utf8).write(to: url)

        let locale = Locale(identifier: "fr_FR")
        let log = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        let caffeine = try #require(log.dailyQuantities(on: day(20), locale: locale).first)
        #expect(caffeine.recordedValue == 12.5)
        #expect(caffeine.text == "12,5")

        let walks = try log.createTypedVariable(
            name: "Walks", kind: .count, defaultValue: .count(0), startsOn: day(20)
        )
        log.editTypedEntry(walks.id, on: day(20), value: .count(2))
        log.editQuantity(caffeine.id, on: day(21), text: "50,5", locale: locale)

        let reopened = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(reopened.dailyQuantity(caffeine.id, on: day(20), locale: locale)?.recordedValue == 12.5)
        #expect(reopened.dailyQuantity(caffeine.id, on: day(21), locale: locale)?.recordedValue == 50.5)
        #expect(reopened.dailyTypedEntries(on: day(20)).map(\.recordedValue) == [.count(2)])
        #expect(reopened.dailyTypedEntries(on: day(21)).map(\.value) == [.count(0)])
    }

    @Test func aFailedTypedAutosaveCanRetryOnItsOriginalDayWithoutLosingTheDraft() throws {
        let url = temporaryStore()
        let directory = url.deletingLastPathComponent()
        let blocked = directory.appendingPathComponent("blocked")
        let backup = directory.appendingPathComponent("backup.json")
        let files = FileManager.default
        defer { try? files.removeItem(at: directory) }

        let store = blocked.appendingPathComponent("manual-log.json")
        let log = HealthAnalysisApplication(manualLogStoreURL: store).manualLog
        let energy = try log.createTypedVariable(
            name: "Energy", kind: .rating(1...5), defaultValue: .rating(3), startsOn: day(19)
        )
        log.editTypedEntry(energy.id, on: day(19), value: .rating(2))
        try files.moveItem(at: store, to: backup)
        try files.removeItem(at: blocked)
        try Data().write(to: blocked)

        log.editTypedEntry(energy.id, on: day(19), value: .rating(5))
        let pending = try #require(log.dailyTypedEntry(energy.id, on: day(19)))
        #expect(pending.status == .saveFailed)
        #expect(pending.recordedValue == .rating(2))
        #expect(pending.value == .rating(2))
        #expect(pending.displayedValue == .rating(5))
        #expect(log.dailyTypedEntry(energy.id, on: day(20))?.status == .assumedDefault)

        try files.removeItem(at: blocked)
        try files.createDirectory(at: blocked, withIntermediateDirectories: false)
        try files.moveItem(at: backup, to: store)
        log.retryTypedEntry(energy.id, on: day(19))

        let reopened = HealthAnalysisApplication(manualLogStoreURL: store).manualLog
        #expect(reopened.dailyTypedEntry(energy.id, on: day(19))?.recordedValue == .rating(5))
        #expect(reopened.dailyTypedEntry(energy.id, on: day(19))?.status == .saved)
        #expect(reopened.dailyTypedEntry(energy.id, on: day(20))?.recordedValue == nil)
    }

    private func temporaryStore() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("manual-log.json")
    }

    private func day(_ day: Int) -> ManualLogDay {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let date = DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: timeZone, year: 2026, month: 11, day: day
        ).date!
        return ManualLogDay(date, timeZone: timeZone)
    }
}
