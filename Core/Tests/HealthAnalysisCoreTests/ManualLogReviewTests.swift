import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct ManualLogReviewTests {
    private let locale = Locale(identifier: "en_US")

    @Test func confirmingMixedValuesPreservesOriginsAndReviewAfterReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("manual-log.json")
        let log = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        let startsOn = day(17)
        let backdatedDay = day(19)
        let caffeine = try log.createQuantity(name: "Caffeine", unit: "mg", defaultValue: 50, startsOn: startsOn)
        let fluids = try log.createQuantity(name: "Water", unit: "mL", defaultValue: 500, startsOn: startsOn)

        log.editQuantity(caffeine.id, on: backdatedDay, text: "0", locale: locale)
        let beforeReview = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(beforeReview.review(on: backdatedDay) == nil)
        #expect(beforeReview.dailyQuantity(caffeine.id, on: backdatedDay, locale: locale)?.recordedValue == 0)

        try log.confirmDay(backdatedDay)
        let reviewedAt = try #require(log.review(on: backdatedDay)?.reviewedAt)
        let reopened = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        let observation = try #require(reopened.dailyQuantity(caffeine.id, on: backdatedDay, locale: locale))
        let assumption = try #require(reopened.dailyQuantity(fluids.id, on: backdatedDay, locale: locale))
        #expect(observation.value == 0)
        #expect(observation.origin == .observation)
        #expect(observation.status == .saved)
        #expect(assumption.value == 500)
        #expect(assumption.recordedValue == nil)
        #expect(assumption.origin == .assumedDefault(effectiveOn: startsOn))
        #expect(assumption.status == .assumedDefault)
        #expect(reopened.review(on: backdatedDay)?.reviewedAt == reviewedAt)
        #expect(reopened.review(on: backdatedDay)?.isCurrent == true)
        #expect(reopened.review(on: day(20)) == nil)
    }

    @Test func defaultVersionsRespectEffectiveDatesAndOlderHistoryRequiresOptIn() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("manual-log.json")
        let log = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        let quantity = try log.createQuantity(name: "Caffeine", unit: "mg", defaultValue: 25, startsOn: day(17))
        log.editQuantity(quantity.id, on: day(20), text: "0", locale: locale)
        try log.confirmDay(day(19))
        let originalReview = log.review(on: day(19))

        try log.setQuantityDefault(quantity.id, value: 50, effectiveOn: day(19))
        try log.setQuantityDefault(quantity.id, value: 75, effectiveOn: day(22))
        #expect(throws: ManualLog.DefaultError.olderHistoryRequiresOptIn) {
            try log.setQuantityDefault(quantity.id, value: 10, effectiveOn: day(15))
        }
        #expect(log.dailyQuantities(on: day(16), locale: locale).isEmpty)
        #expect(throws: ManualLog.ReviewError.noFields) { try log.confirmDay(day(16)) }
        #expect(throws: ManualLog.DefaultError.dateMustPrecedeHistory) {
            try log.setQuantityDefault(quantity.id, value: 10, effectiveOn: day(17), scope: .olderHistory)
        }
        try log.setQuantityDefault(quantity.id, value: 10, effectiveOn: day(15), scope: .olderHistory)

        let reopened = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(reopened.quantities.map(\.id) == [quantity.id])
        #expect(reopened.quantityDefaults(quantity.id).map(\.effectiveOn) == [day(15), day(17), day(19), day(22)])
        #expect(reopened.dailyQuantities(on: day(14), locale: locale).isEmpty)
        #expect(reopened.dailyQuantity(quantity.id, on: day(15), locale: locale)?.value == 10)
        #expect(reopened.dailyQuantity(quantity.id, on: day(16), locale: locale)?.value == 10)
        #expect(reopened.dailyQuantity(quantity.id, on: day(17), locale: locale)?.value == 25)
        #expect(reopened.dailyQuantity(quantity.id, on: day(19), locale: locale)?.value == 25)
        #expect(reopened.dailyQuantity(quantity.id, on: day(19), locale: locale)?.origin == .assumedDefault(effectiveOn: day(17)))
        #expect(reopened.review(on: day(19)) == originalReview)
        #expect(reopened.dailyQuantity(quantity.id, on: day(20), locale: locale)?.recordedValue == 0)
        #expect(reopened.dailyQuantity(quantity.id, on: day(21), locale: locale)?.value == 50)
        #expect(reopened.dailyQuantity(quantity.id, on: day(21), locale: locale)?.origin == .assumedDefault(effectiveOn: day(19)))
        #expect(reopened.dailyQuantity(quantity.id, on: day(22), locale: locale)?.value == 75)
    }

    @Test func invalidEditsBlockReviewAndChangingSavedValuesRequiresAnotherReview() throws {
        let log = HealthAnalysisApplication().manualLog
        let date = day(19)
        let quantity = try log.createQuantity(name: "Caffeine", unit: "mg", defaultValue: 25, startsOn: date)
        try log.confirmDay(date)
        let reviewedAt = log.review(on: date)?.reviewedAt

        log.editQuantity(quantity.id, on: date, text: "-", locale: locale)
        #expect(!log.canConfirmDay(date))
        #expect(throws: ManualLog.ReviewError.unresolvedEdits) { try log.confirmDay(date) }
        #expect(log.review(on: date)?.reviewedAt == reviewedAt)
        #expect(log.dailyQuantity(quantity.id, on: date, locale: locale)?.value == 25)
        #expect(log.canConfirmDay(day(20)))

        log.editQuantity(quantity.id, on: date, text: "25", locale: locale)
        #expect(log.canConfirmDay(date))
        #expect(log.dailyQuantity(quantity.id, on: date, locale: locale)?.status == .saved)
        #expect(log.review(on: date)?.isCurrent == false)
        try log.confirmDay(date)
        #expect(log.review(on: date)?.isCurrent == true)
        #expect(log.dailyQuantity(quantity.id, on: date, locale: locale)?.origin == .observation)
    }

    @Test func dayReviewIncludesTypedValuesAndBlocksTheirUnresolvedEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("manual-log.json")
        let log = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        let date = day(19)
        let count = try log.createTypedVariable(name: "Walks", kind: .count, defaultValue: .count(2), startsOn: date)

        #expect(log.canConfirmDay(date))
        if log.canConfirmDay(date) { try log.confirmDay(date) }
        #expect(log.review(on: date)?.isCurrent == true)
        #expect(throws: ManualLog.DefaultError.olderHistoryRequiresOptIn) {
            try log.setTypedDefault(count.id, value: .count(1), effectiveOn: day(17))
        }
        #expect(log.dailyTypedEntry(count.id, on: day(18)) == nil)
        try log.setTypedDefault(count.id, value: .count(1), effectiveOn: day(17), scope: .olderHistory)
        try log.setTypedDefault(count.id, value: .count(3), effectiveOn: date)
        let backfilled = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(backfilled.dailyTypedEntry(count.id, on: day(18))?.value == .count(1))
        #expect(backfilled.dailyTypedEntry(count.id, on: date)?.value == .count(2))
        #expect(backfilled.dailyTypedEntry(count.id, on: date)?.origin == .assumedDefault(effectiveOn: date))
        #expect(backfilled.dailyTypedEntry(count.id, on: date)?.recordedValue == nil)
        #expect(backfilled.dailyTypedEntry(count.id, on: day(20))?.value == .count(3))
        #expect(backfilled.review(on: date)?.isCurrent == true)

        let quantity = try log.createQuantity(name: "Caffeine", unit: "mg", defaultValue: 25, startsOn: date)
        log.editQuantity(quantity.id, on: date, text: "0", locale: locale)
        log.editTypedEntry(count.id, on: date, value: .count(-1))
        #expect(!log.canConfirmDay(date))
        #expect(throws: ManualLog.ReviewError.unresolvedEdits) { try log.confirmDay(date) }

        log.editTypedEntry(count.id, on: date, value: .count(0))
        try log.confirmDay(date)
        let reopened = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(reopened.review(on: date)?.isCurrent == true)
        #expect(reopened.dailyTypedEntry(count.id, on: date)?.recordedValue == .count(0))
        #expect(reopened.dailyTypedEntry(count.id, on: date)?.origin == .observation)
        reopened.editTypedEntry(count.id, on: date, value: .count(1))
        #expect(reopened.review(on: date)?.isCurrent == false)
    }

    @Test func failedWritesLeaveReviewAndObservationUnchangedUntilRetry() throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: directory) }
        let store = directory.appendingPathComponent("store")
        let movedStore = directory.appendingPathComponent("moved-store")
        let url = store.appendingPathComponent("manual-log.json")
        let log = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        let date = day(19)
        let nextDate = day(20)
        let quantity = try log.createQuantity(name: "Caffeine", unit: "mg", defaultValue: 25, startsOn: date)
        log.editQuantity(quantity.id, on: date, text: "10", locale: locale)
        try files.moveItem(at: store, to: movedStore)
        try Data().write(to: store)

        log.editQuantity(quantity.id, on: date, text: "15", locale: locale)
        #expect(log.dailyQuantity(quantity.id, on: date, locale: locale)?.text == "15")
        #expect(log.dailyQuantity(quantity.id, on: date, locale: locale)?.status == .saveFailed)
        #expect(!log.canConfirmDay(date))
        #expect(throws: ManualLog.ReviewError.unresolvedEdits) { try log.confirmDay(date) }
        #expect(throws: ManualLog.ReviewError.persistenceFailed) { try log.confirmDay(nextDate) }
        #expect(throws: ManualLog.DefaultError.persistenceFailed) {
            try log.setQuantityDefault(quantity.id, value: 50, effectiveOn: nextDate)
        }
        #expect(log.dailyQuantity(quantity.id, on: nextDate, locale: locale)?.value == 25)
        #expect(log.review(on: nextDate) == nil)

        try files.removeItem(at: store)
        try files.moveItem(at: movedStore, to: store)
        let beforeRetry = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(beforeRetry.dailyQuantity(quantity.id, on: date, locale: locale)?.recordedValue == 10)
        #expect(beforeRetry.review(on: date) == nil)
        #expect(beforeRetry.review(on: nextDate) == nil)

        log.retryQuantity(quantity.id, on: date)
        try log.confirmDay(date)
        let reopened = HealthAnalysisApplication(manualLogStoreURL: url).manualLog
        #expect(reopened.dailyQuantity(quantity.id, on: date, locale: locale)?.recordedValue == 15)
        #expect(reopened.review(on: date)?.isCurrent == true)
    }

    private func day(_ day: Int) -> ManualLogDay {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: timeZone, year: 2026, month: 11, day: day).date!
        return ManualLogDay(date, timeZone: timeZone)
    }
}
