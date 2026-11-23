import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct ManualLogTests {
    private let french = Locale(identifier: "fr_FR")
    private var firstDay: ManualLogDay { logDay(20) }
    private var previousDay: ManualLogDay { logDay(19) }

    @Test func quantityUsesItsConfiguredDefaultFromTheChosenStartDateAfterReopening() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("manual-log.json")

        let application = HealthAnalysisApplication(manualLogStoreURL: url)
        #expect(!application.overview.hasTrackingVariables)
        let quantity = try application.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 37.5, startsOn: firstDay
        )
        #expect(application.overview.hasTrackingVariables)

        let reopened = HealthAnalysisApplication(manualLogStoreURL: url)
        #expect(reopened.overview.hasTrackingVariables)
        #expect(reopened.manualLog.quantities == [quantity])
        #expect(quantity.name == "Caffeine")
        #expect(quantity.unit == "mg")
        #expect(quantity.startsOn == firstDay)
        #expect(reopened.manualLog.dailyQuantities(on: previousDay, locale: french).isEmpty)
        let row = try #require(reopened.manualLog.dailyQuantities(on: firstDay, locale: french).first)
        #expect(row.value == 37.5)
        #expect(row.text == "37,5")
        #expect(row.recordedValue == nil)
        #expect(row.status == .assumedDefault)
    }

    @Test func backdatedEditsAutosaveByDayAndAnExplicitZeroSurvivesReopening() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("manual-log.json")
        let application = HealthAnalysisApplication(manualLogStoreURL: url)
        let quantity = try application.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 50, startsOn: previousDay
        )

        application.manualLog.editQuantity(quantity.id, on: firstDay, text: "125,75", locale: french)
        let backdated = try #require(application.manualLog.dailyQuantities(on: previousDay, locale: french).first)
        #expect(backdated.value == 50)
        #expect(backdated.status == .assumedDefault)
        application.manualLog.editQuantity(quantity.id, on: previousDay, text: "0", locale: french)

        let reopened = HealthAnalysisApplication(manualLogStoreURL: url)
        let firstRow = try #require(reopened.manualLog.dailyQuantities(on: firstDay, locale: french).first)
        #expect(firstRow.recordedValue == 125.75)
        #expect(firstRow.text == "125,75")
        #expect(firstRow.status == .saved)
        let backdatedRow = try #require(reopened.manualLog.dailyQuantities(on: previousDay, locale: french).first)
        #expect(backdatedRow.recordedValue == 0)
        #expect(backdatedRow.status == .saved)
    }

    @Test func invalidAndIncompleteEditsRetainTheDraftAndPreserveTheSavedValue() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("manual-log.json")
        let application = HealthAnalysisApplication(manualLogStoreURL: url)
        let quantity = try application.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 0, startsOn: firstDay
        )
        application.manualLog.editQuantity(quantity.id, on: firstDay, text: "24,5", locale: french)

        for text in ["", "-", "24,", "24,5mg", "24.5", "1,2,3"] {
            application.manualLog.editQuantity(quantity.id, on: firstDay, text: text, locale: french)
            let row = try #require(application.manualLog.dailyQuantities(on: firstDay, locale: french).first)
            #expect(row.text == text)
            #expect(row.status == .invalid)
            #expect(row.recordedValue == 24.5)
        }

        let reopened = HealthAnalysisApplication(manualLogStoreURL: url)
        let row = try #require(reopened.manualLog.dailyQuantities(on: firstDay, locale: french).first)
        #expect(row.status == .saved)
        #expect(row.recordedValue == 24.5)
    }

    @Test func failedAutosaveKeepsItsOriginalDayAndRetriesWithoutRetyping() throws {
        let directory = try temporaryDirectory()
        let files = FileManager.default
        defer { try? files.removeItem(at: directory) }
        let store = directory.appendingPathComponent("store")
        let movedStore = directory.appendingPathComponent("moved-store")
        let url = store.appendingPathComponent("manual-log.json")
        let application = HealthAnalysisApplication(manualLogStoreURL: url)
        let quantity = try application.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 20, startsOn: previousDay
        )
        application.manualLog.editQuantity(quantity.id, on: previousDay, text: "7", locale: french)
        try files.moveItem(at: store, to: movedStore)
        try Data().write(to: store)

        application.manualLog.editQuantity(quantity.id, on: previousDay, text: "12,5", locale: french)
        let today = try #require(application.manualLog.dailyQuantities(on: firstDay, locale: french).first)
        #expect(today.status == .assumedDefault)
        application.manualLog.retryQuantity(quantity.id, on: previousDay)
        let failed = try #require(application.manualLog.dailyQuantities(on: previousDay, locale: french).first)
        #expect(failed.text == "12,5")
        #expect(failed.recordedValue == 7)
        #expect(failed.status == .saveFailed)

        try files.removeItem(at: store)
        try files.moveItem(at: movedStore, to: store)
        let beforeRetry = HealthAnalysisApplication(manualLogStoreURL: url)
        #expect(beforeRetry.manualLog.dailyQuantities(on: previousDay, locale: french).first?.recordedValue == 7)

        application.manualLog.retryQuantity(quantity.id, on: previousDay)
        let saved = try #require(application.manualLog.dailyQuantities(on: previousDay, locale: french).first)
        #expect(saved.text == "12,5")
        #expect(saved.status == .saved)
        let reopened = HealthAnalysisApplication(manualLogStoreURL: url)
        #expect(reopened.manualLog.dailyQuantities(on: previousDay, locale: french).first?.recordedValue == 12.5)
        #expect(reopened.manualLog.dailyQuantities(on: firstDay, locale: french).first?.recordedValue == nil)
    }

    @Test func movingTheLegacyLogPreservesEntriesAndReviewsAcrossReopen() throws {
        let directory = try temporaryDirectory()
        let files = FileManager.default
        defer { try? files.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("manual-log.json")
        let localDirectory = directory.appendingPathComponent("ManualLog")
        let local = localDirectory.appendingPathComponent("manual-log.json")
        let original = HealthAnalysisApplication(manualLogStoreURL: legacy)
        let quantity = try original.manualLog.createQuantity(
            name: "Adjustment", unit: "mg", defaultValue: 0, startsOn: previousDay
        )
        original.manualLog.editQuantity(quantity.id, on: previousDay, text: "-7", locale: french)
        try original.manualLog.confirmDay(previousDay)
        try Data().write(to: localDirectory)

        let migrated = HealthAnalysisApplication(manualLogStoreURL: local, legacyManualLogStoreURL: legacy)
        #expect(migrated.manualLog.dailyQuantity(quantity.id, on: previousDay, locale: french)?.recordedValue == -7)
        #expect(files.fileExists(atPath: legacy.path))
        try files.removeItem(at: localDirectory)
        migrated.manualLog.editQuantity(quantity.id, on: firstDay, text: "8", locale: french)

        #expect(!files.fileExists(atPath: legacy.path))
        let reopened = HealthAnalysisApplication(manualLogStoreURL: local, legacyManualLogStoreURL: legacy)
        #expect(reopened.manualLog.dailyQuantity(quantity.id, on: firstDay, locale: french)?.recordedValue == 8)
        #expect(reopened.manualLog.dailyQuantity(quantity.id, on: previousDay, locale: french)?.recordedValue == -7)
        #expect(reopened.manualLog.review(on: previousDay) != nil)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func logDay(_ day: Int) -> ManualLogDay {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: timeZone, year: 2026, month: 11, day: day).date!
        return ManualLogDay(date, timeZone: timeZone)
    }
}
