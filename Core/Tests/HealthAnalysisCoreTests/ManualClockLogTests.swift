import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct ManualClockLogTests {
    @Test func backdatedClockReadingsKeepTheirDayAndPrecisionAfterTravel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("manual-log.json")
        let log = HealthAnalysisApplication(manualLogStoreURL: store).manualLog
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let formatter = ISO8601DateFormatter()
        let springInstant = try #require(formatter.date(from: "2026-03-08T17:00:00Z"))
        let fallInstant = try #require(formatter.date(from: "2026-11-01T17:00:00Z"))
        let springDay = ManualLogDay(springInstant, timeZone: newYork)
        let fallDay = ManualLogDay(fallInstant, timeZone: newYork)
        let defaultTime = ManualTrackingValue.timeOfDay(ManualClockTime(hour: 12, minute: 0))
        let caffeine = try log.createTypedVariable(
            name: "Last caffeine", kind: .timeOfDay, defaultValue: defaultTime, startsOn: springDay
        )

        let skippedHour = ManualTrackingValue.timeOfDay(ManualClockTime(hour: 2, minute: 30), precision: .approximate)
        let repeatedHour = ManualTrackingValue.timeOfDay(ManualClockTime(hour: 1, minute: 30), precision: .exact)
        log.editTypedEntry(caffeine.id, on: springDay, value: skippedHour)
        log.editTypedEntry(caffeine.id, on: fallDay, value: repeatedHour)

        let reopened = HealthAnalysisApplication(manualLogStoreURL: store).manualLog
        let springInTokyo = try #require(formatter.date(from: "2026-03-08T03:00:00Z"))
        let fallInTokyo = try #require(formatter.date(from: "2026-11-01T03:00:00Z"))
        #expect(reopened.dailyTypedEntry(caffeine.id, on: ManualLogDay(springInTokyo, timeZone: tokyo))?.recordedValue == skippedHour)
        #expect(reopened.dailyTypedEntry(caffeine.id, on: ManualLogDay(fallInTokyo, timeZone: tokyo))?.recordedValue == repeatedHour)
        let nextDayInTokyo = ManualLogDay(fallInstant, timeZone: tokyo)
        #expect(reopened.dailyTypedEntry(caffeine.id, on: nextDayInTokyo)?.recordedValue == nil)
        #expect(reopened.dailyTypedEntry(caffeine.id, on: nextDayInTokyo)?.value == defaultTime)
    }

    @Test func effectiveClockDefaultsStayAssumptionsWhenTheDayIsReviewed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("manual-log.json")
        let log = HealthAnalysisApplication(manualLogStoreURL: store).manualLog
        let start = day(19)
        let later = day(20)
        let earlier = day(18)
        let midnight = ManualTrackingValue.timeOfDay(ManualClockTime(hour: 0, minute: 0))
        let lastMinute = ManualTrackingValue.timeOfDay(ManualClockTime(hour: 23, minute: 59))
        let exactMidnight = ManualTrackingValue.timeOfDay(ManualClockTime(hour: 0, minute: 0), precision: .exact)
        #expect(throws: ManualLog.TypedVariableCreationError.invalidDefinition) {
            try log.createTypedVariable(name: "Last caffeine", kind: .timeOfDay, defaultValue: exactMidnight, startsOn: start)
        }
        let caffeine = try log.createTypedVariable(
            name: "Last caffeine", kind: .timeOfDay, defaultValue: midnight, startsOn: start
        )
        #expect(log.dailyTypedEntries(on: earlier).isEmpty)
        #expect(throws: ManualLog.DefaultError.olderHistoryRequiresOptIn) {
            try log.setTypedDefault(caffeine.id, value: lastMinute, effectiveOn: earlier)
        }
        #expect(throws: ManualLog.DefaultError.invalidValue) {
            try log.setTypedDefault(caffeine.id, value: exactMidnight, effectiveOn: later)
        }

        try log.confirmDay(start)
        try log.setTypedDefault(caffeine.id, value: lastMinute, effectiveOn: start)
        try log.setTypedDefault(caffeine.id, value: lastMinute, effectiveOn: earlier, scope: .olderHistory)

        let reopened = HealthAnalysisApplication(manualLogStoreURL: store).manualLog
        #expect(reopened.review(on: start)?.isCurrent == true)
        #expect(reopened.dailyTypedEntry(caffeine.id, on: start)?.value == midnight)
        #expect(reopened.dailyTypedEntry(caffeine.id, on: start)?.origin == .assumedDefault(effectiveOn: start))
        #expect(reopened.dailyTypedEntry(caffeine.id, on: start)?.recordedValue == nil)
        #expect(reopened.dailyTypedEntry(caffeine.id, on: earlier)?.value == lastMinute)
        #expect(reopened.dailyTypedEntry(caffeine.id, on: later)?.value == lastMinute)

        reopened.editTypedEntry(caffeine.id, on: start, value: midnight)
        #expect(reopened.dailyTypedEntry(caffeine.id, on: start)?.recordedValue == exactMidnight)
        #expect(reopened.review(on: start)?.isCurrent == false)
        try reopened.confirmDay(start)
        let approximateMidnight = ManualTrackingValue.timeOfDay(ManualClockTime(hour: 0, minute: 0), precision: .approximate)
        reopened.editTypedEntry(caffeine.id, on: start, value: approximateMidnight)
        #expect(reopened.review(on: start)?.isCurrent == false)
    }

    @Test func invalidAndFailedClockEditsPreserveTheLastSavedReadingUntilRetry() throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: directory) }
        let storeDirectory = directory.appendingPathComponent("store")
        let backup = directory.appendingPathComponent("backup")
        let store = storeDirectory.appendingPathComponent("manual-log.json")
        let log = HealthAnalysisApplication(manualLogStoreURL: store).manualLog
        let date = day(19)
        let nextDate = day(20)
        let defaultTime = ManualTrackingValue.timeOfDay(ManualClockTime(hour: 12, minute: 0))
        let caffeine = try log.createTypedVariable(
            name: "Last caffeine", kind: .timeOfDay, defaultValue: defaultTime, startsOn: date
        )
        let saved = ManualTrackingValue.timeOfDay(ManualClockTime(hour: 22, minute: 10), precision: .exact)
        log.editTypedEntry(caffeine.id, on: date, value: saved)
        try log.confirmDay(date)

        for invalid in [ManualClockTime(hour: 24, minute: 0), ManualClockTime(hour: 10, minute: 60)] {
            log.editTypedEntry(caffeine.id, on: date, value: .timeOfDay(invalid, precision: .approximate))
            #expect(log.dailyTypedEntry(caffeine.id, on: date)?.status == .invalid)
            #expect(log.dailyTypedEntry(caffeine.id, on: date)?.displayedValue == saved)
            #expect(throws: ManualLog.ReviewError.unresolvedEdits) { try log.confirmDay(date) }
        }

        try files.moveItem(at: storeDirectory, to: backup)
        try Data().write(to: storeDirectory)
        let recalled = ManualTrackingValue.timeOfDay(ManualClockTime(hour: 23, minute: 59), precision: .approximate)
        log.editTypedEntry(caffeine.id, on: date, value: recalled)
        #expect(log.dailyTypedEntry(caffeine.id, on: date)?.status == .saveFailed)
        #expect(log.dailyTypedEntry(caffeine.id, on: date)?.displayedValue == recalled)
        #expect(log.dailyTypedEntry(caffeine.id, on: date)?.recordedValue == saved)
        #expect(!log.canConfirmDay(date))
        #expect(log.canConfirmDay(nextDate))
        #expect(log.dailyTypedEntry(caffeine.id, on: nextDate)?.value == defaultTime)

        try files.removeItem(at: storeDirectory)
        try files.moveItem(at: backup, to: storeDirectory)
        let beforeRetry = HealthAnalysisApplication(manualLogStoreURL: store).manualLog
        #expect(beforeRetry.dailyTypedEntry(caffeine.id, on: date)?.recordedValue == saved)
        #expect(beforeRetry.review(on: date)?.isCurrent == true)
        log.retryTypedEntry(caffeine.id, on: nextDate)
        #expect(log.dailyTypedEntry(caffeine.id, on: date)?.status == .saveFailed)
        log.retryTypedEntry(caffeine.id, on: date)

        let reopened = HealthAnalysisApplication(manualLogStoreURL: store).manualLog
        #expect(reopened.dailyTypedEntry(caffeine.id, on: date)?.recordedValue == recalled)
        #expect(reopened.dailyTypedEntry(caffeine.id, on: nextDate)?.recordedValue == nil)
        #expect(reopened.review(on: date)?.isCurrent == false)
    }

    private func day(_ day: Int) -> ManualLogDay {
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: .gmt, year: 2026, month: 11, day: day).date!
        return ManualLogDay(date, timeZone: .gmt)
    }
}
