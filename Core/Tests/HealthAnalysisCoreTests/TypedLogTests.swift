import Foundation
import HealthAnalysisCore
import Testing

@Suite struct TypedLogTests {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let today = Date(timeIntervalSince1970: 1_710_072_000)

    @Test func explicitCountZeroSurvivesInvalidInputAndReopeningOnTheOriginalDay() throws {
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone, locale: Locale(identifier: "fr_FR"))
            let day = session.logDay
            let earlier = LogDay(today.addingTimeInterval(-86_400), timeZone: zone)
            let count = try session.createLogVariable(name: "Coffee", kind: .count(unit: "cups"), defaultValue: .count(0), startDay: earlier)
            let quantity = try session.createQuantity(name: "Coffee", unit: "mg", defaultText: "12,5", effectiveDay: earlier)
            #expect(session.typedLogFields(on: earlier).first?.assumedDefault == .count(0))
            #expect(session.typedObservation(for: count.id, on: earlier) == nil)
            #expect(session.logStatus(on: earlier) == .unmarked)

            session.selectLogDay(earlier)
            session.editCount(count.id, on: session.logDay, text: "٠")
            for invalid in ["", "-1", "1,5", "1,0", "1b", "9223372036854775808"] {
                session.editCount(count.id, on: session.logDay, text: invalid)
                #expect(session.countText(count.id, on: earlier) == invalid)
                #expect(session.typedLogFields(on: earlier).first?.feedback == .invalidNumber)
                #expect(session.typedObservation(for: count.id, on: earlier) == LogObservation(value: .count(0), origin: .recorded))
            }
            #expect(session.dayConfirmation(on: earlier)?.canSave == false)
            session.editCount(count.id, on: session.logDay, text: "0")
            session.editQuantity(quantity.id, on: earlier, text: "82,5")
            session.selectLogDay(day)
            session.editCount(count.id, on: session.logDay, text: "1 234")

            let reopened = HealthAnalysisSession(
                storeURL: url, today: today, timeZone: TimeZone(identifier: "Asia/Tokyo")!, locale: Locale(identifier: "ar_EG")
            )
            #expect(reopened.typedLogFields(on: earlier).first?.id == count.id)
            #expect(reopened.typedLogFields(on: earlier).first?.variable.kind == .count(unit: "cups"))
            #expect(reopened.typedObservation(for: count.id, on: earlier) == LogObservation(value: .count(0), origin: .recorded))
            #expect(reopened.typedObservation(for: count.id, on: day)?.value == .count(1234))
            #expect(reopened.countText(count.id, on: earlier) == "٠")
            #expect(reopened.countText(count.id, on: day) == "١٢٣٤")
            #expect(reopened.observation(for: quantity.id, on: earlier)?.value == Decimal(string: "82.5"))
            #expect(reopened.logStatus(on: earlier) == .editsSaved)
        }
    }

    @Test func confirmingADayRecordsItsDisplayedDefaultsAndKeepsExplicitChoices() throws {
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone)
            let day = session.logDay
            let earlier = LogDay(today.addingTimeInterval(-86_400), timeZone: zone)
            let count = try session.createLogVariable(name: "Coffee", kind: .count(unit: nil), defaultValue: .count(0), startDay: earlier)
            let exercised = try session.createLogVariable(name: "Exercised", kind: .yesNo, defaultValue: .yesNo(false), startDay: earlier)
            let meditated = try session.createLogVariable(name: "Meditated", kind: .yesNo, defaultValue: .yesNo(false), startDay: earlier)
            let low = LogOption(label: "Low")
            let high = LogOption(label: "High")
            let rating = try session.createLogVariable(name: "Energy", kind: .rating([low, high]), defaultValue: .option(low.id), startDay: earlier)
            let office = LogOption(label: "Office")
            let home = LogOption(label: "Home")
            let location = try session.createLogVariable(name: "Location", kind: .category([office, home]), startDay: earlier)
            let quantity = try session.createQuantity(name: "Coffee", unit: "mg", defaultText: "0", effectiveDay: day)

            #expect(session.typedLogFields(on: earlier).map(\.id) == [count.id, exercised.id, meditated.id, rating.id, location.id])
            #expect(session.typedObservation(for: exercised.id, on: day) == nil)
            #expect(session.typedObservation(for: rating.id, on: day) == nil)
            session.editTypedValue(exercised.id, on: day, value: .yesNo(false))
            session.editTypedValue(rating.id, on: day, value: .option(office.id))
            #expect(session.logStatus(on: day) == .editsSaved)
            #expect(session.typedObservation(for: rating.id, on: day) == nil)

            session.confirmDay(day)
            #expect(session.logStatus(on: day) == .confirmed)
            let confirmed = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone)
            #expect(confirmed.observation(for: quantity.id, on: day)?.origin == .confirmedDefault)
            #expect(confirmed.typedObservation(for: count.id, on: day) == LogObservation(value: .count(0), origin: .confirmedDefault))
            #expect(confirmed.typedObservation(for: exercised.id, on: day) == LogObservation(value: .yesNo(false), origin: .recorded))
            #expect(confirmed.typedObservation(for: meditated.id, on: day) == LogObservation(value: .yesNo(false), origin: .confirmedDefault))
            #expect(confirmed.typedObservation(for: rating.id, on: day) == LogObservation(value: .option(low.id), origin: .confirmedDefault))
            #expect(confirmed.typedObservation(for: location.id, on: day) == nil)

            session.editTypedValue(meditated.id, on: day, value: .yesNo(false))
            session.editTypedValue(rating.id, on: day, value: .option(high.id))
            session.editTypedValue(location.id, on: earlier, value: .option(home.id))
            let reopened = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone)
            #expect(reopened.logVariables.first(where: { $0.id == rating.id })?.kind == .rating([low, high]))
            #expect(reopened.logVariables.first(where: { $0.id == location.id })?.kind == .category([office, home]))
            #expect(reopened.typedObservation(for: meditated.id, on: day) == LogObservation(value: .yesNo(false), origin: .recorded))
            #expect(reopened.typedObservation(for: rating.id, on: day) == LogObservation(value: .option(high.id), origin: .recorded))
            #expect(reopened.typedObservation(for: rating.id, on: earlier) == nil)
            #expect(reopened.typedObservation(for: location.id, on: earlier) == LogObservation(value: .option(home.id), origin: .recorded))
            #expect(reopened.typedObservation(for: location.id, on: day) == nil)
            #expect(reopened.logStatus(on: day) == .confirmed)
            #expect(reopened.logStatus(on: earlier) == .editsSaved)
        }
    }

    @Test func failedChoiceStaysOnItsOriginalDayUntilRetried() throws {
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone)
            let day = session.logDay
            let earlier = LogDay(today.addingTimeInterval(-86_400), timeZone: zone)
            let exercised = try session.createLogVariable(name: "Exercised", kind: .yesNo, defaultValue: .yesNo(true), startDay: earlier)
            session.selectLogDay(earlier)

            let backup = url.appendingPathExtension("backup")
            try FileManager.default.moveItem(at: url, to: backup)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            session.editTypedValue(exercised.id, on: session.logDay, value: .yesNo(false))
            session.selectLogDay(day)

            let failed = try #require(session.typedLogFields(on: earlier).first)
            #expect(failed.pendingValue == .yesNo(false))
            #expect(failed.feedback == .saveFailed)
            #expect(failed.observation == nil)
            #expect(session.dayConfirmation(on: earlier)?.canSave == false)
            #expect(session.typedLogFields(on: day).first?.pendingValue == nil)
            #expect(session.logStatus(on: earlier) == .unmarked)

            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: backup, to: url)
            session.retryTypedEdit(exercised.id, on: earlier)
            #expect(session.typedLogFields(on: earlier).first?.pendingValue == nil)
            #expect(session.typedLogFields(on: earlier).first?.feedback == nil)
            let reopened = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone)
            #expect(reopened.typedObservation(for: exercised.id, on: earlier) == LogObservation(value: .yesNo(false), origin: .recorded))
            #expect(reopened.typedObservation(for: exercised.id, on: day) == nil)
            #expect(reopened.logStatus(on: earlier) == .editsSaved)
        }
    }

    @Test func changingTypedDefaultsKeepsConfirmedHistoryAndRequiresAnExplicitBackdate() throws {
        try withStore { url in
            var session = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone)
            let day = session.logDay
            let reviewed = LogDay(today.addingTimeInterval(-86_400), timeZone: zone)
            let effective = LogDay(today.addingTimeInterval(-172_800), timeZone: zone)
            let start = LogDay(today.addingTimeInterval(-259_200), timeZone: zone)
            let exercise = try session.createLogVariable(name: "Exercised", kind: .yesNo, defaultValue: .yesNo(false), startDay: start)
            session.confirmDay(reviewed)

            #expect(throws: LogVariableSettingsError.earlierDefaultRequiresConfirmation) {
                try session.changeLogDefault(exercise.id, to: .yesNo(true), effectiveDay: effective, today: day)
            }
            #expect(session.typedLogFields(on: effective).first?.assumedDefault == .yesNo(false))
            try session.changeLogDefault(
                exercise.id, to: .yesNo(true), effectiveDay: effective, applyToEarlierDays: true, today: day
            )
            try session.changeLogDefault(exercise.id, to: nil, effectiveDay: day, today: day)

            let reopened = HealthAnalysisSession(storeURL: url, today: today, timeZone: zone)
            #expect(reopened.logVariables.first?.id == exercise.id)
            #expect(reopened.logVariables.first?.latestDefaultDay == day)
            #expect(reopened.logVariables.first?.latestDefaultValue == nil)
            #expect(reopened.typedLogFields(on: start).first?.assumedDefault == .yesNo(false))
            #expect(reopened.typedLogFields(on: effective).first?.assumedDefault == .yesNo(true))
            #expect(reopened.typedObservation(for: exercise.id, on: effective) == nil)
            #expect(reopened.typedObservation(for: exercise.id, on: reviewed) == LogObservation(value: .yesNo(false), origin: .confirmedDefault))
            #expect(reopened.typedLogFields(on: day).first?.assumedDefault == nil)
            #expect(reopened.logStatus(on: day) == .unmarked)
        }
    }

    private func withStore(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("DailyLog.json"))
    }
}
