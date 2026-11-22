import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct FirstUseTests {
    @Test func firstUseChecksReadableCoverageAndCanFinishWithoutChangingTracking() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appending(path: "health.json")
        let setupURL = directory.appending(path: "setup")
        let logURL = directory.appending(path: "log.json")
        let source = FirstUseSource(records: [
            restingHeartRate(on: day(1)),
            restingHeartRate(on: day(3))
        ])
        let app = HealthAnalysisApplication(
            healthSource: source, healthHistoryStoreURL: historyURL,
            manualLogStoreURL: logURL, firstUseStoreURL: setupURL
        )

        #expect(app.firstUse.step == .healthAccess)
        #expect(app.healthMeasurements.readState == .idle)
        await app.firstUse.requestHealthAccess()
        #expect(app.firstUse.step == .coverage)
        #expect(app.healthMeasurements.readState == .loaded)
        let coverage = try #require(app.healthMeasurements.coverage(for: .restingHeartRate, calendar: calendar))
        #expect(coverage.firstMeasurement == day(1))
        #expect(coverage.latestMeasurement == day(3))
        #expect(coverage.measuredDays == 2)
        #expect(coverage.daysWithoutMeasurements == 1)
        #expect(app.healthMeasurements.coverage(for: .sleepAnalysis) == nil)

        app.firstUse.continueToTracking()
        #expect(app.firstUse.step == .manualTracking)
        try app.firstUse.finish()
        let reopened = HealthAnalysisApplication(
            healthHistoryStoreURL: historyURL, manualLogStoreURL: logURL, firstUseStoreURL: setupURL
        )
        #expect(reopened.firstUse.step == .complete)
        #expect(!reopened.overview.hasTrackingVariables)
        #expect(reopened.overview.hasReadableMeasurements)
    }

    @Test func readablePresetsUseSupportedInputsAndOpenAnEditableSleepQuestion() async throws {
        let watch = HealthMeasurement.Source(name: "Watch", bundleIdentifier: "fixture.watch")
        let bedtime = day(3).addingTimeInterval(13 * 3600)
        let wake = day(4).addingTimeInterval(-3 * 3600)
        let app = HealthAnalysisApplication(healthSource: FirstUseSource(records: [
            restingHeartRate(on: day(3)),
            HealthMeasurement(
                id: UUID(), sleepStage: .asleepUnspecified, startDate: bedtime, endDate: wake,
                source: watch, timeZoneIdentifier: "GMT"
            ),
            HealthMeasurement(
                id: UUID(), metric: HRVSeries.StoredType.sdnn.metric, value: 43, unit: .milliseconds,
                startDate: day(3), endDate: day(3), source: watch
            )
        ]))
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 0, startsOn: logDay(1)
        )
        let alcohol = try app.manualLog.createTypedVariable(
            name: "Alcohol drinks", kind: .count, defaultValue: .count(0), startsOn: logDay(1)
        )
        app.manualLog.editTypedEntry(alcohol.id, on: logDay(2), value: .count(2))
        let stress = try app.manualLog.createTypedVariable(
            name: "Stress", kind: .rating(1...5), defaultValue: .rating(3), startsOn: logDay(1)
        )
        for (day, value) in [(2, "90"), (3, "900")] {
            app.manualLog.editQuantity(
                caffeine.id, on: logDay(day), text: value, locale: Locale(identifier: "en_US")
            )
        }
        await app.firstUse.requestHealthAccess()
        app.firstUse.continueToTracking()
        try app.firstUse.finish()

        #expect(!app.healthMeasurements.hrvSeries(for: .sdnn).isEmpty)
        let presets = app.analysisPresets(timeZone: .gmt, asOf: day(4))
        #expect(Set(presets.map(\.output)) == [.health(metric: .sleepAnalysis), .health(metric: .restingHeartRate)])
        #expect(presets.count == 6)
        #expect(Set(presets.flatMap(\.inputs)) == [.manualQuantity(caffeine.id), .manualTyped(alcohol.id), .manualTyped(stress.id)])
        let drinksAndSleep = try #require(presets.first {
            $0.output == .health(metric: .sleepAnalysis) && $0.inputs == [.manualTyped(alcohol.id)]
        })
        #expect(drinksAndSleep.behaviorWindow == .precedingDay)
        let countResult = try app.analyze(drinksAndSleep, asOf: day(4))
        #expect(countResult.observations.first?.inputs.first?.value == 2)
        var longerCountQuestion = drinksAndSleep
        longerCountQuestion.behaviorWindow = .precedingWeek
        #expect(throws: AnalysisRunFailure.countWindowUnavailable) {
            try app.analyze(longerCountQuestion, asOf: day(4))
        }
        #expect(throws: AnalysisRunFailure.unsupportedConfiguration) {
            try app.analyze(.init(
                output: .health(metric: HRVSeries.StoredType.sdnn.metric), inputs: [.manualQuantity(caffeine.id)]
            ), asOf: day(4))
        }
        var sleep = try #require(presets.first {
            $0.output == .health(metric: .sleepAnalysis) && $0.inputs == [.manualQuantity(caffeine.id)]
        })
        #expect(sleep.behaviorWindow == .precedingDay)
        #expect(sleep.history == .fullHistory)
        sleep.history = .last90Days
        let result = try app.analyze(sleep, asOf: day(4))
        #expect(result.configuration == sleep)
        let observation = try #require(result.observations.first)
        #expect(observation.outputAnchor == wake)
        #expect(observation.outputValue == 8)
        #expect(observation.inputs.map(\.value) == [90])
    }

    @Test func anEditedTrackingSuggestionKeepsItsIdentityAndStartsOnTheChosenDay() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appending(path: "health.json")
        let logURL = directory.appending(path: "log.json")
        let app = HealthAnalysisApplication(
            healthSource: FirstUseSource(records: [restingHeartRate(on: day(2)), restingHeartRate(on: day(3))]),
            healthHistoryStoreURL: historyURL, manualLogStoreURL: logURL
        )
        await app.firstUse.requestHealthAccess()
        app.firstUse.continueToTracking()
        #expect(app.manualLog.suggestedTrackingVariables.contains(.caffeine))
        let quantity = try app.manualLog.createQuantity(
            name: "Morning espresso", unit: "mg", defaultValue: 80, startsOn: logDay(2), suggestion: .caffeine
        )
        try app.firstUse.finish()

        let reopened = HealthAnalysisApplication(healthHistoryStoreURL: historyURL, manualLogStoreURL: logURL)
        #expect(!reopened.manualLog.suggestedTrackingVariables.contains(.caffeine))
        #expect(reopened.manualLog.dailyQuantity(quantity.id, on: logDay(1), locale: .current) == nil)
        let defaultedDay = try #require(reopened.manualLog.dailyQuantity(quantity.id, on: logDay(2), locale: .current))
        #expect(defaultedDay.value == 80)
        #expect(defaultedDay.origin == .assumedDefault(effectiveOn: logDay(2)))

        let preset = try #require(reopened.analysisPresets(timeZone: .gmt, asOf: day(4)).first)
        #expect(preset.inputs == [.manualQuantity(quantity.id)])
        let result = try reopened.analyze(preset, asOf: day(4))
        #expect(result.coverage.outputDaysWithoutCompleteInput == 1)
        #expect(result.observations.map { $0.inputs[0].value } == [80])
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2025, month: 3, day: day, hour: 9))!
    }

    private func logDay(_ day: Int) -> ManualLogDay { ManualLogDay(self.day(day), timeZone: .gmt) }

    private func restingHeartRate(on date: Date) -> HealthMeasurement {
        HealthMeasurement(
            id: UUID(), metric: .restingHeartRate, value: 61, unit: .beatsPerMinute,
            startDate: date, endDate: date, source: .init(name: "Watch", bundleIdentifier: "fixture.watch")
        )
    }
}

private actor FirstUseSource: HealthMeasurementSource {
    let records: [HealthMeasurement]
    private var requestedAccess = false

    init(records: [HealthMeasurement]) {
        self.records = records
    }

    func requestReadAccess() async throws { requestedAccess = true }

    func readChanges(
        after anchors: [String: Data], includingPreviouslySaved: Bool
    ) async throws -> [HealthMeasurementChanges] {
        guard requestedAccess else { throw HealthMeasurementReadFailure.request }
        return [.init(queryID: "fixture", anchor: Data([1]), added: records)]
    }
}
