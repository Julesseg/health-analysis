import Foundation
import HealthAnalysisCore
import Testing

@Suite struct DailyLogTests {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let locale = Locale(identifier: "en_US")

    @Test func defaultStartsOnItsEffectiveDayAndDoesNotCreateAnObservation() throws {
        let start = Date(timeIntervalSince1970: 1_710_072_000)
        let previous = LogDay(start.addingTimeInterval(-86_400), timeZone: zone)
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, today: start, timeZone: zone, locale: locale)
            let day = session.logDay
            let quantity = try session.createQuantity(name: "Caffeine", unit: "mg", defaultText: "40", effectiveDay: day)

            let field = try #require(session.logFields(on: day).first)
            #expect(field.quantity.name == "Caffeine")
            #expect(field.quantity.unit == "mg")
            #expect(field.assumedDefault == "40")
            #expect(session.logFields(on: previous).isEmpty)
            #expect(session.recordedQuantity(quantity.id, on: day) == nil)
            #expect(!session.hasSavedEdits(on: day))

            let reopened = HealthAnalysisSession(storeURL: url, today: start, timeZone: zone, locale: locale)
            #expect(reopened.logFields(on: day).first?.quantity.id == quantity.id)
            #expect(reopened.logFields(on: day).first?.assumedDefault == "40")
            #expect(reopened.recordedQuantity(quantity.id, on: day) == nil)
        }
    }

    @Test func confirmingADayKeepsDefaultZeroDistinctFromRecordedZero() throws {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let skipped = LogDay(today.addingTimeInterval(-86_400), timeZone: zone)
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            let day = session.logDay
            let caffeine = try session.createQuantity(name: "Caffeine", unit: "mg", defaultText: "0", effectiveDay: skipped)
            let exercise = try session.createQuantity(name: "Exercise", unit: "min", defaultText: "20", effectiveDay: skipped)
            session.editQuantity(exercise.id, on: day, text: "0")
            #expect(session.observation(for: caffeine.id, on: day) == nil)
            #expect(session.observation(for: exercise.id, on: day) == LogQuantityObservation(value: 0, origin: .recorded))
            #expect(session.logStatus(on: day) == .editsSaved)

            session.confirmDay(day)
            #expect(session.logStatus(on: day) == .confirmed)
            #expect(session.observation(for: caffeine.id, on: day) == LogQuantityObservation(value: 0, origin: .confirmedDefault))
            #expect(session.recordedQuantity(caffeine.id, on: day) == nil)
            #expect(session.logFields(on: day).first?.assumedDefault == nil)
            #expect(session.logFields(on: day).first?.observationOrigin == .confirmedDefault)
            #expect(session.quantityText(caffeine.id, on: day) == "0")
            #expect(session.observation(for: exercise.id, on: day)?.origin == .recorded)
            #expect(session.observation(for: caffeine.id, on: skipped) == nil)
            #expect(session.logStatus(on: skipped) == .unmarked)

            session.editQuantity(caffeine.id, on: day, text: "0")
            session.editQuantity(exercise.id, on: day, text: "12")
            let reopened = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            #expect(reopened.logStatus(on: day) == .confirmed)
            #expect(reopened.observation(for: caffeine.id, on: day) == LogQuantityObservation(value: 0, origin: .recorded))
            #expect(reopened.observation(for: exercise.id, on: day) == LogQuantityObservation(value: 12, origin: .recorded))
        }
    }

    @Test func failedConfirmationKeepsSavedEditsAndCanBeRetriedOnTheOriginalDay() throws {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier = LogDay(today.addingTimeInterval(-86_400), timeZone: zone)
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            let day = session.logDay
            let caffeine = try session.createQuantity(name: "Caffeine", unit: "mg", defaultText: "50", effectiveDay: earlier)
            let exercise = try session.createQuantity(name: "Exercise", unit: "min", defaultText: "0", effectiveDay: earlier)
            session.editQuantity(exercise.id, on: day, text: "0")
            session.editQuantity(caffeine.id, on: day, text: "1.")
            #expect(session.dayConfirmation(on: day)?.canSave == false)
            session.confirmDay(day)
            #expect(session.logStatus(on: day) == .editsSaved)
            session.editQuantity(caffeine.id, on: day, text: "10")

            let backup = url.appendingPathExtension("backup")
            try FileManager.default.moveItem(at: url, to: backup)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            session.confirmDay(earlier)
            session.selectLogDay(earlier)
            #expect(session.dayConfirmation(on: earlier)?.saveFailed == true)
            #expect(session.logStatus(on: earlier) == .unmarked)
            #expect(session.observation(for: caffeine.id, on: earlier) == nil)
            #expect(session.observation(for: exercise.id, on: earlier) == nil)
            session.selectLogDay(day)
            #expect(session.dayConfirmation(on: day)?.saveFailed == false)
            #expect(session.logStatus(on: day) == .editsSaved)

            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: backup, to: url)
            let beforeRetry = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            #expect(beforeRetry.logStatus(on: earlier) == .unmarked)
            #expect(beforeRetry.logFields(on: earlier).first?.assumedDefault == "50")

            session.confirmDay(earlier)
            #expect(session.dayConfirmation(on: earlier) == nil)
            session.confirmDay(day)
            let reopened = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            #expect(reopened.logStatus(on: earlier) == .confirmed)
            #expect(reopened.logStatus(on: day) == .confirmed)
            #expect(reopened.observation(for: caffeine.id, on: earlier) == LogQuantityObservation(value: 50, origin: .confirmedDefault))
            #expect(reopened.observation(for: exercise.id, on: earlier) == LogQuantityObservation(value: 0, origin: .confirmedDefault))
        }
    }

    @Test func recordingTheOnlyNewValueClearsAFailedConfirmationOnAReviewedDay() throws {
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, timeZone: zone, locale: locale)
            let day = session.logDay
            let caffeine = try session.createQuantity(name: "Caffeine", unit: "mg", defaultText: "0", effectiveDay: day)
            session.confirmDay(day)
            let exercise = try session.createQuantity(name: "Exercise", unit: "min", defaultText: "20", effectiveDay: day)
            #expect(session.dayConfirmation(on: day)?.canSave == true)
            #expect(session.observation(for: exercise.id, on: day) == nil)

            let backup = url.appendingPathExtension("backup")
            try FileManager.default.moveItem(at: url, to: backup)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            session.confirmDay(day)
            #expect(session.dayConfirmation(on: day)?.saveFailed == true)
            session.editQuantity(caffeine.id, on: day, text: "1")
            let failedCorrection = try #require(session.logFields(on: day).first)
            #expect(failedCorrection.feedback == .saveFailed)
            #expect(failedCorrection.savedValue == "0")
            #expect(failedCorrection.observationOrigin == .confirmedDefault)
            #expect(session.observation(for: caffeine.id, on: day)?.origin == .confirmedDefault)

            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: backup, to: url)
            session.editQuantity(exercise.id, on: day, text: "15")
            #expect(session.logStatus(on: day) == .confirmed)
            #expect(session.dayConfirmation(on: day) == nil)
            #expect(session.logFields(on: day).first?.feedback == .saveFailed)
            try session.createQuantity(name: "Water", unit: "mL", defaultText: "0", effectiveDay: day)
            #expect(session.dayConfirmation(on: day)?.saveFailed == false)
        }
    }

    @Test func backdatedDefaultRequiresOptInAndPreservesExistingObservations() throws {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        func daysAgo(_ count: Int) -> LogDay {
            LogDay(today.addingTimeInterval(-86_400 * Double(count)), timeZone: zone)
        }
        let start = daysAgo(5)
        let effectiveDay = daysAgo(4)
        let entered = daysAgo(3)
        let confirmed = daysAgo(2)
        let skipped = daysAgo(1)
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            let day = session.logDay
            let caffeine = try session.createQuantity(name: "Caffeine", unit: "mg", defaultText: "0", effectiveDay: start)
            session.editQuantity(caffeine.id, on: entered, text: "0")
            session.confirmDay(confirmed)
            try session.updateQuantity(
                caffeine.id, name: caffeine.name, unit: caffeine.unit, startDay: start, endDay: nil,
                defaultChange: ("20", day), today: day
            )
            #expect(session.logFields(on: skipped).first?.assumedDefault == "0")
            #expect(throws: QuantitySettingsError.earlierDefaultRequiresConfirmation) {
                try session.updateQuantity(
                    caffeine.id, name: caffeine.name, unit: caffeine.unit, startDay: start, endDay: nil,
                    defaultChange: ("10", effectiveDay), today: day
                )
            }
            #expect(session.logFields(on: skipped).first?.assumedDefault == "0")
            try session.updateQuantity(
                caffeine.id, name: caffeine.name, unit: caffeine.unit, startDay: start, endDay: nil,
                defaultChange: ("10", effectiveDay), applyDefaultToEarlierDays: true, today: day
            )

            let reopened = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            #expect(reopened.logFields(on: start).first?.assumedDefault == "0")
            #expect(reopened.logFields(on: effectiveDay).first?.assumedDefault == "10")
            #expect(reopened.observation(for: caffeine.id, on: entered) == LogQuantityObservation(value: 0, origin: .recorded))
            #expect(reopened.observation(for: caffeine.id, on: confirmed) == LogQuantityObservation(value: 0, origin: .confirmedDefault))
            #expect(reopened.logFields(on: skipped).first?.assumedDefault == "10")
            #expect(reopened.logStatus(on: skipped) == .unmarked)
            #expect(reopened.observation(for: caffeine.id, on: skipped) == nil)
            #expect(reopened.logFields(on: day).first?.assumedDefault == "20")
        }
    }

    @Test func explicitZeroAndBackdatedCorrectionsSurviveReopeningInAnotherTimeZone() throws {
        let dates = ISO8601DateFormatter()
        let today = try #require(dates.date(from: "2024-03-10T19:00:00Z"))
        let backdated = try #require(dates.date(from: "2024-03-10T07:30:00Z"))
        let justBeforeDst = LogDay(backdated, timeZone: zone)
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let march9InTokyo = try #require(dates.date(from: "2024-03-09T06:00:00Z"))
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            let day = session.logDay
            let first = try session.createQuantity(name: "Caffeine", unit: "mg", defaultText: "0", effectiveDay: justBeforeDst)
            let second = try session.createQuantity(name: "Caffeine", unit: "mg", defaultText: "25", effectiveDay: day)

            session.editQuantity(first.id, on: day, text: "0")
            session.selectLogDay(justBeforeDst)
            session.editQuantity(first.id, on: justBeforeDst, text: "12")
            session.editQuantity(first.id, on: justBeforeDst, text: "9.5")
            session.selectLogDay(day)
            #expect(session.quantityText(first.id, on: session.logDay) == "0")

            let reopened = HealthAnalysisSession(storeURL: url, today: today, timeZone: tokyo, locale: locale)
            let sameCivilDay = LogDay(march9InTokyo, timeZone: tokyo)
            #expect(reopened.recordedQuantity(first.id, on: sameCivilDay) == Decimal(string: "9.5"))
            #expect(reopened.recordedQuantity(first.id, on: day) == 0)
            #expect(reopened.recordedQuantity(second.id, on: day) == nil)
            #expect(reopened.hasSavedEdits(on: sameCivilDay))
            #expect(reopened.hasSavedEdits(on: day))
            #expect(!reopened.hasSavedEdits(on: reopened.logDay))
        }
    }

    @Test func localizedDraftSurvivesInvalidInputAndFailedSaveUntilRetriedOnItsDay() throws {
        let locale = Locale(identifier: "fr_FR")
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, timeZone: zone, locale: locale)
            let day = session.logDay
            let otherDay = LogDay(day.date(in: zone).addingTimeInterval(-86_400), timeZone: zone)
            let quantity = try session.createQuantity(name: "Caféine", unit: "mg", defaultText: "1,5", effectiveDay: otherDay)
            #expect(session.logFields(on: day).first?.assumedDefault == "1,5")

            session.editQuantity(quantity.id, on: day, text: "2,75")
            session.editQuantity(quantity.id, on: day, text: "2,75x")
            #expect(session.quantityText(quantity.id, on: day) == "2,75x")
            #expect(session.logFields(on: day).first?.feedback == .invalidNumber)
            #expect(session.recordedQuantity(quantity.id, on: day) == Decimal(string: "2.75"))
            session.editQuantity(quantity.id, on: day, text: "3,")
            #expect(session.logFields(on: day).first?.feedback == .invalidNumber)
            #expect(session.recordedQuantity(quantity.id, on: day) == Decimal(string: "2.75"))

            let backup = url.appendingPathExtension("backup")
            try FileManager.default.moveItem(at: url, to: backup)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            session.editQuantity(quantity.id, on: day, text: "3,50")
            session.selectLogDay(otherDay)
            #expect(session.logFields(on: session.logDay).first?.assumedDefault == "1,5")
            #expect(!session.hasSavedEdits(on: otherDay))
            #expect(session.quantityText(quantity.id, on: day) == "3,50")
            #expect(session.logFields(on: day).first?.feedback == .saveFailed)
            #expect(session.recordedQuantity(quantity.id, on: day) == Decimal(string: "2.75"))

            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: backup, to: url)
            session.retryQuantity(quantity.id, on: day)
            #expect(session.logFields(on: day).first?.feedback == nil)
            let reopened = HealthAnalysisSession(storeURL: url, timeZone: zone, locale: locale)
            #expect(reopened.quantityText(quantity.id, on: day) == "3,5")
            #expect(reopened.recordedQuantity(quantity.id, on: otherDay) == nil)
        }
    }

    @Test func localizedGroupingAndMinusSignPreserveDecimalPrecision() throws {
        try withStore { url in
            var french = HealthAnalysisSession(storeURL: url, timeZone: zone, locale: Locale(identifier: "fr_FR"))
            let day = french.logDay
            let quantity = try french.createQuantity(name: "Caféine", unit: "mg", defaultText: "1 234,5", effectiveDay: day)
            #expect(french.logFields(on: day).first?.assumedDefault == "1234,5")

            var swedish = HealthAnalysisSession(storeURL: url, timeZone: zone, locale: Locale(identifier: "sv_SE"))
            swedish.editQuantity(quantity.id, on: day, text: "−1 234,567890123456789")
            let expected = Decimal(string: "-1234.567890123456789", locale: Locale(identifier: "en_US_POSIX"))
            #expect(swedish.recordedQuantity(quantity.id, on: day) == expected)
            swedish.editQuantity(quantity.id, on: day, text: "−12 34,5")
            #expect(swedish.logFields(on: day).first?.feedback == .invalidNumber)
            #expect(swedish.recordedQuantity(quantity.id, on: day) == expected)
        }
    }

    @Test func unreadableLogCanBeRetriedWithoutBlockingAnalysisOrReplacingItsFile() throws {
        try withStore { url in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = Data("Unreadable log".utf8)
            try original.write(to: url)

            var session = HealthAnalysisSession(storeURL: url, timeZone: zone, locale: locale)
            #expect(session.tab == .analysis)
            #expect(!session.isLogAvailable)
            session.selectTab(.log)
            #expect(throws: QuantitySettingsError.saveFailed) {
                try session.createQuantity(name: "Caffeine", unit: "mg", defaultText: "0", effectiveDay: session.logDay)
            }
            #expect(try Data(contentsOf: url) == original)
            session.selectTab(.analysis)
            #expect(session.tab == .analysis)

            try FileManager.default.removeItem(at: url)
            session.selectTab(.log)
            session.retryOpeningLog()
            #expect(session.isLogAvailable)
            #expect(session.logFields(on: session.logDay).isEmpty)
        }
    }

    @Test func editingAndArchivingChangesWhichDaysShowTheQuantityAndKeepsItsHistory() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let start = LogDay(try #require(calendar.date(byAdding: .day, value: -3, to: today)), timeZone: zone)
        let end = LogDay(try #require(calendar.date(byAdding: .day, value: -1, to: today)), timeZone: zone)
        let beforeStart = LogDay(try #require(calendar.date(byAdding: .day, value: -4, to: today)), timeZone: zone)
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            let quantity = try session.createQuantity(name: "Caffeine", unit: "mg", defaultText: "10", effectiveDay: start)
            session.editQuantity(quantity.id, on: start, text: "7")
            try session.updateQuantity(
                quantity.id, name: "Coffee", unit: "mg", startDay: start, endDay: end,
                defaultChange: (text: "12", effectiveDay: end), today: end
            )
            session.editQuantity(quantity.id, on: session.logDay, text: "8")
            session.editQuantity(quantity.id, on: beforeStart, text: "9")

            let reopened = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            #expect(reopened.quantities.first?.id == quantity.id)
            #expect(reopened.quantities.first?.endDay == end)
            #expect(reopened.logFields(on: start).first?.quantity.name == "Coffee")
            #expect(reopened.recordedQuantity(quantity.id, on: start) == 7)
            let middle = LogDay(try #require(calendar.date(byAdding: .day, value: -2, to: today)), timeZone: zone)
            #expect(reopened.logFields(on: middle).first?.assumedDefault == "10")
            #expect(reopened.logFields(on: end).first?.assumedDefault == "12")
            #expect(reopened.logFields(on: reopened.logDay).isEmpty)
            #expect(reopened.logFields(on: beforeStart).isEmpty)
            #expect(!reopened.hasSavedEdits(on: reopened.logDay))
            #expect(!reopened.hasSavedEdits(on: beforeStart))
        }
    }

    @Test func removingAQuantityKeepsOtherObservationsAndClearsItsDayMarker() throws {
        try withStore { url in
            let today = Date(timeIntervalSince1970: 1_700_000_000)
            var session = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            let day = session.logDay
            let earlier = LogDay(today.addingTimeInterval(-172_800), timeZone: zone)
            let reviewed = LogDay(today.addingTimeInterval(-86_400), timeZone: zone)
            let first = try session.createQuantity(name: "Coffee", unit: "mg", defaultText: "0", effectiveDay: earlier)
            let second = try session.createQuantity(name: "Exercise", unit: "min", defaultText: "0", effectiveDay: earlier)
            session.editQuantity(first.id, on: earlier, text: "10")
            session.editQuantity(first.id, on: day, text: "15")
            session.editQuantity(second.id, on: day, text: "20")
            session.confirmDay(reviewed)
            #expect(throws: QuantitySettingsError.endDateWouldRemoveEntries(2)) {
                try session.updateQuantity(first.id, name: "Coffee", unit: "mg", startDay: earlier, endDay: earlier)
            }
            #expect(session.recordedQuantity(first.id, on: day) == 15)
            #expect(session.quantities.first?.endDay == nil)
            try session.updateQuantity(
                first.id, name: "Coffee", unit: "mg", startDay: earlier, endDay: earlier, removeEntriesAfterEnd: true
            )
            let archived = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            #expect(archived.quantities.first?.endDay == earlier)
            #expect(archived.recordedQuantity(first.id, on: earlier) == 10)
            #expect(archived.recordedQuantity(first.id, on: day) == nil)
            #expect(archived.observation(for: first.id, on: reviewed) == nil)
            #expect(archived.observation(for: second.id, on: reviewed) == LogQuantityObservation(value: 0, origin: .confirmedDefault))
            #expect(archived.logStatus(on: reviewed) == .confirmed)
            #expect(archived.recordedQuantity(second.id, on: day) == 20)
            try session.removeQuantity(first.id)

            let reopened = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: locale)
            #expect(reopened.quantities.map(\.id) == [second.id])
            #expect(reopened.recordedQuantity(first.id, on: earlier) == nil)
            #expect(!reopened.hasSavedEdits(on: earlier))
            #expect(reopened.recordedQuantity(second.id, on: day) == 20)
            #expect(reopened.hasSavedEdits(on: day))
        }
    }

    @Test func reopeningThePreviousStoreKeepsEntriesThatPredateTheFirstDefault() throws {
        let id = try #require(UUID(uuidString: "E24718B5-535D-4AAF-9A1E-F5BD391104F7"))
        let backdated = try #require(ISO8601DateFormatter().date(from: "2024-03-09T20:00:00Z"))
        let day = LogDay(backdated, timeZone: zone)
        try withStore { url in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let legacy = """
                {"quantities":[{"id":"\(id.uuidString)","name":"Coffee","unit":"mg","defaultValue":5,
                "effectiveDay":{"year":2024,"month":3,"day":10}}],
                "entries":[{"year":2024,"month":3,"day":9},["\(id.uuidString)",7]]}
                """
            try Data(legacy.utf8).write(to: url)
            let reopened = HealthAnalysisSession(storeURL: url, today: backdated, timeZone: zone, locale: locale)
            #expect(reopened.quantities.first?.startDay == day)
            #expect(reopened.logFields(on: day).first?.id == id)
            #expect(reopened.recordedQuantity(id, on: day) == 7)
            #expect(reopened.observation(for: id, on: day)?.origin == .recorded)
            #expect(reopened.logStatus(on: day) == .editsSaved)
        }
    }

    private func withStore(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("DailyLog.json"))
    }
}
