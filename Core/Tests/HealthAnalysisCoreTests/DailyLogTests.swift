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
            #expect(session.logFields(on: previous).first?.assumedDefault == nil)
            #expect(session.recordedQuantity(quantity.id, on: day) == nil)
            #expect(!session.hasSavedEdits(on: day))

            let reopened = HealthAnalysisSession(storeURL: url, today: start, timeZone: zone, locale: locale)
            #expect(reopened.logFields(on: day).first?.quantity.id == quantity.id)
            #expect(reopened.logFields(on: day).first?.assumedDefault == "40")
            #expect(reopened.recordedQuantity(quantity.id, on: day) == nil)
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
            let first = try session.createQuantity(name: "Caffeine", unit: "mg", defaultText: "0", effectiveDay: day)
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
            #expect(throws: QuantityCreationError.saveFailed) {
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

    private func withStore(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("DailyLog.json"))
    }
}
