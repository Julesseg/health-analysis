import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct ClockAnalysisTests {
    @Test func adjustedClockQuestionComparesAnHourAcrossMidnightAndSurvivesReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appending(path: "log.json")
        let saved = directory.appending(path: "saved.json")
        let app = HealthAnalysisApplication(manualLogStoreURL: log, savedAnalysesStoreURL: saved)
        let caffeine = try clock("Last caffeine", starts: 0, in: app)
        let bedtime = try clock("Bedtime", starts: 1, in: app)
        let coffees = try app.manualLog.createTypedVariable(
            name: "Coffees", kind: .count, defaultValue: .count(0), startsOn: day(0)
        )

        for index in 0..<100 {
            let late = index % 2
            let dose = index / 2 % 2
            let outputMinute = 23 * 60 + 40 + 30 * late + 10 * dose + (index / 4 % 5 - 2)
            app.manualLog.editTypedEntry(caffeine, on: day(index), value: time(
                late == 1 ? 30 : 23 * 60 + 30, precision: index % 5 == 0 ? .approximate : .exact
            ))
            app.manualLog.editTypedEntry(bedtime, on: day(index + 1), value: time(
                outputMinute % 1440, precision: index % 10 == 0 ? .approximate : .exact
            ))
            app.manualLog.editTypedEntry(coffees.id, on: day(index), value: .count(dose))
        }
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let configuration = AnalysisConfiguration(
            output: .manualTyped(bedtime), inputs: [.manualTyped(caffeine)],
            adjustmentInputs: [.manualTyped(coffees.id)], timeZone: zone
        )
        let choice = try #require(app.analysisVariables.first { $0.id == .manualTyped(caffeine) })
        #expect(choice.supportsInput && choice.supportsOutput)
        let reopened = HealthAnalysisApplication(manualLogStoreURL: log, savedAnalysesStoreURL: saved)
        let result = try reopened.analyze(configuration, asOf: date(102))
        #expect(result.coverage.usableDates.count == 100)
        #expect(result.evidence.grade == .low)
        let caffeineEffect = try #require(result.estimates.first)
        #expect(caffeineEffect.inputIncrement == 60)
        #expect(caffeineEffect.scale == .clockMinutesDifference)
        #expect(result.clockIntervals?.first?.startMinute == 1410)
        #expect(result.clockIntervals?.first?.endMinute == 30)
        #expect(abs(caffeineEffect.difference - 30) < 0.001)
        #expect(abs((try #require(result.estimates.last)).difference - 10) < 0.001)
        #expect(caffeineEffect.interval.lowerBound > 25)
        #expect(result.inputEvidence(for: .manualTyped(caffeine)).approximateCount == 20)
        #expect(result.observations.first?.outputTrackingValue == time(23 * 60 + 38, precision: .approximate))
        #expect(result.observations[1].inputs[0].trackingValue == time(30))
        let question = try reopened.savedAnalyses.save(configuration)
        let again = HealthAnalysisApplication(manualLogStoreURL: log, savedAnalysesStoreURL: saved)
        #expect(again.savedAnalyses.question(id: question.id)?.configuration == configuration)
        await again.refreshSavedAnalysis(question.id)
        #expect(again.savedAnalyses.state(for: question.id).completed?.result.configuration == configuration)
        let afterRefresh = HealthAnalysisApplication(manualLogStoreURL: log, savedAnalysesStoreURL: saved)
        let savedResult = try #require(afterRefresh.savedAnalyses.state(for: question.id).completed?.result)
        #expect(savedResult.clockIntervals?.first?.startMinute == 1410)
        #expect(savedResult.inputEvidence(for: .manualTyped(caffeine)).approximateCount == 20)
    }

    @Test func sleepTimingPresetsKeepEventInstantsAndLocalClocksDuringTravelAndDST() async throws {
        let paris = sleep("2026-03-28T22:30:00Z", "2026-03-29T01:30:00Z", zone: "Europe/Paris")
        let nap = sleep("2026-03-29T11:00:00Z", "2026-03-29T11:30:00Z", zone: "Europe/Paris")
        let tokyo = sleep("2026-04-02T14:30:00Z", "2026-04-02T22:00:00Z", zone: "Asia/Tokyo")
        let newYork = sleep("2026-10-31T23:30:00Z", "2026-11-01T06:30:00Z", zone: "America/New_York")
        let app = HealthAnalysisApplication(healthSource: ClockSleepSource(records: [nap, newYork, tokyo, paris]))
        await app.healthMeasurements.refresh()
        let caffeine = try clock("Last caffeine", starts: 0, in: app)
        let analysisZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        let asOf = date("2026-11-03T00:00:00Z")
        let presets = app.analysisPresets(timeZone: analysisZone, asOf: asOf)
        let onset = try #require(presets.first {
            $0.output == .sleepTiming(.onset) && $0.inputs == [.manualTyped(caffeine)]
        })
        let wake = try #require(presets.first {
            $0.output == .sleepTiming(.wake) && $0.inputs == [.manualTyped(caffeine)]
        })
        let onsetResult = try app.analyze(onset, asOf: asOf)
        let wakeResult = try app.analyze(wake, asOf: asOf)
        #expect(onsetResult.observations.map(\.outputAnchor) == [paris.startDate, tokyo.startDate, newYork.startDate])
        #expect(wakeResult.observations.map(\.outputAnchor) == [paris.endDate, tokyo.endDate, newYork.endDate])
        let onsetMinutes: [Double] = [1410, 1410, 1170]
        let wakeMinutes: [Double] = [210, 420, 90]
        #expect(onsetResult.observations.map(\.outputValue) == onsetMinutes)
        #expect(wakeResult.observations.map(\.outputValue) == wakeMinutes)
        #expect(wakeResult.outputEvidence.compactMap(\.sleepTimeZoneEvidence) == [
            .sampleMetadata(identifier: "Europe/Paris", sampleID: paris.id),
            .sampleMetadata(identifier: "Asia/Tokyo", sampleID: tokyo.id),
            .sampleMetadata(identifier: "America/New_York", sampleID: newYork.id)
        ])
        let outputDays = wakeResult.observations.map { ManualLogDay($0.outputDate, timeZone: analysisZone) }
        let behaviorDays = wakeResult.observations.map { ManualLogDay($0.inputs[0].date, timeZone: analysisZone) }
        #expect(outputDays.map(\.day) == [29, 3, 1])
        #expect(behaviorDays.map(\.day) == [27, 1, 30])
    }

    @Test func wideOrUnrecordedClockIntervalsWithholdTheEstimateAndExplainWhy() throws {
        let app = HealthAnalysisApplication()
        let caffeine = try clock("Last caffeine", starts: 0, in: app)
        let output = try clock("Bedtime", starts: 1, in: app)
        let series = AnalysisSeriesID.manualTyped(caffeine)
        var configuration = AnalysisConfiguration(output: .manualTyped(output), inputs: [series], timeZone: .gmt)
        for index in 0..<48 {
            app.manualLog.editTypedEntry(caffeine, on: day(index), value: time([0, 480, 960][index % 3]))
            app.manualLog.editTypedEntry(output, on: day(index + 1), value: time(index % 2 == 0 ? 1410 : 30))
        }
        let wide = try app.analyze(configuration, asOf: date(49))
        #expect(wide.estimates.isEmpty)
        #expect(wide.evidence.reasons.contains(.clockIntervalUnavailable([series])))
        for index in 0..<48 {
            app.manualLog.editTypedEntry(caffeine, on: day(index), value: time(150))
        }
        let constant = try app.analyze(configuration, asOf: date(49))
        #expect(constant.estimates.isEmpty)
        #expect(constant.evidence.reasons.contains(.limitedRecordedClockVariation([series])))

        configuration.behaviorWindow = .precedingWeek
        #expect(throws: AnalysisRunFailure.clockWindowUnavailable) {
            try app.analyze(configuration, asOf: date(49))
        }
        let moderator = try clock("Wake time", starts: 0, in: app)
        configuration.behaviorWindow = .precedingDay
        configuration.inputs.append(.manualTyped(moderator))
        configuration.interaction = AnalysisInteraction(focal: series, moderator: .manualTyped(moderator))
        #expect(throws: AnalysisRunFailure.clockInteractionUnavailable) {
            try app.analyze(configuration, asOf: date(49))
        }
    }

    @Test func clockContrastNeedsAnObservedHourAndRetainsTheYesNoOutputModel() throws {
        let app = HealthAnalysisApplication()
        let caffeine = try clock("Last caffeine", starts: 0, in: app)
        let headache = try app.manualLog.createTypedVariable(
            name: "Headache", kind: .yesNo, defaultValue: .yesNo(false), startsOn: day(1)
        )
        let series = AnalysisSeriesID.manualTyped(caffeine)
        let configuration = AnalysisConfiguration(output: .manualTyped(headache.id), inputs: [series], timeZone: .gmt)
        for index in 0..<96 {
            let late = index % 2 == 1
            app.manualLog.editTypedEntry(caffeine, on: day(index), value: time(late ? 15 : 1410))
            let event = index / 2 % 4 < (late ? 3 : 1)
            app.manualLog.editTypedEntry(headache.id, on: day(index + 1), value: .yesNo(event))
        }
        let narrow = try app.analyze(configuration, asOf: date(97))
        #expect(narrow.estimates.isEmpty)
        #expect(narrow.evidence.reasons.contains(.clockIncrementUnavailable([series])))

        for index in stride(from: 1, to: 96, by: 2) {
            app.manualLog.editTypedEntry(caffeine, on: day(index), value: time(30))
        }
        let result = try app.analyze(configuration, asOf: date(97))
        let estimate = try #require(result.estimates.first)
        #expect(result.model == .binaryLogisticV1)
        #expect(estimate.scale == .probabilityDifference)
        #expect(abs(estimate.difference - 0.50) < 0.001)
    }

    @Test func categoryAndClockQuestionsPreserveNamedLevelsAndTheirEffectScales() throws {
        let app = HealthAnalysisApplication()
        let caffeine = try clock("Last caffeine", starts: 0, in: app)
        let bedtime = try clock("Bedtime", starts: 1, in: app)
        let home = TrackingCategory(name: "Home")
        let office = TrackingCategory(name: "Office")
        let setting = try app.manualLog.createTypedVariable(
            name: "Work setting", kind: .category([office, home]), defaultValue: .category(home.id), startsOn: day(0)
        )
        for index in 0..<120 {
            let late = index % 2 == 1
            let atOffice = index / 2 % 4 < (late ? 3 : 1)
            app.manualLog.editTypedEntry(caffeine, on: day(index), value: time(late ? 30 : 1410))
            app.manualLog.editTypedEntry(setting.id, on: day(index), value: .category(atOffice ? office.id : home.id))
            let minute = (1410 + (atOffice ? 60 : 0) + index / 8 % 3 - 1) % 1440
            app.manualLog.editTypedEntry(bedtime, on: day(index + 1), value: time(minute))
        }
        let clockInput = AnalysisSeriesID.manualTyped(caffeine)
        let categorySeries = AnalysisSeriesID.manualTyped(setting.id)
        let bedtimeSeries = AnalysisSeriesID.manualTyped(bedtime)
        let clockResult = try app.analyze(.init(
            output: bedtimeSeries, inputs: [categorySeries], timeZone: .gmt,
            categories: .init(inputContrasts: [categorySeries: .init(reference: home.id, comparison: office.id)])
        ), asOf: date(121))
        let clockEffect = try #require(clockResult.estimates.first)
        #expect(clockEffect.scale == .clockMinutesDifference)
        #expect(abs(clockEffect.difference - 60) < 0.001)
        #expect(clockResult.clockIntervals?.first?.series == bedtimeSeries)
        #expect(clockResult.categoryEvidence?.inputLevels[categorySeries]?.map(\.category.id) == [home.id, office.id])

        let categoryResult = try app.analyze(.init(
            output: categorySeries, inputs: [clockInput], timeZone: .gmt,
            categories: .init(outputEvent: office.id)
        ), asOf: date(120))
        let categoryEffect = try #require(categoryResult.estimates.first)
        #expect(categoryResult.model == .categoryEventLogisticV1)
        #expect(categoryEffect.scale == .proportionalCategoryOddsChange)
        #expect(categoryEffect.inputIncrement == 60)
        #expect(categoryResult.clockIntervals?.first?.startMinute == 1410)
        #expect(Set(categoryResult.categoryEvidence?.outputLevels.map(\.category.id) ?? []) == [home.id, office.id])
    }

    @Test func clockIntervalsTrackKnownAssociationsWithPersistentDayToDayNoise() throws {
        var random = ClockRandom()
        var covered = 0
        var totalError = 0.0
        var totalWidth = 0.0
        for trial in 0..<48 {
            let app = HealthAnalysisApplication()
            let caffeine = try clock("Last caffeine", starts: 0, in: app)
            let bedtime = try clock("Bedtime", starts: 1, in: app)
            let effect = trial.isMultiple(of: 2) ? 0 : 24
            var noise = 0.0
            for index in 0..<240 {
                let late = random.next() >= 0.5
                noise = 0.7 * noise + 65 * (random.next() - 0.5)
                app.manualLog.editTypedEntry(caffeine, on: day(index), value: time(late ? 30 : 1410))
                let minute = (1434 + (late ? effect : 0) + Int(noise.rounded()) + 1440) % 1440
                app.manualLog.editTypedEntry(bedtime, on: day(index + 1), value: time(minute))
            }
            let configuration = AnalysisConfiguration(
                output: .manualTyped(bedtime), inputs: [.manualTyped(caffeine)], timeZone: .gmt
            )
            let result = try app.analyze(configuration, asOf: date(241))
            let estimate = try #require(result.estimates.first)
            if estimate.interval.contains(Double(effect)) { covered += 1 }
            totalError += estimate.difference - Double(effect)
            totalWidth += estimate.interval.upperBound - estimate.interval.lowerBound
        }
        #expect(covered >= 38)
        #expect(abs(totalError / 48) < 2)
        #expect(totalWidth / 48 < 24)
    }

    private func sleep(_ start: String, _ end: String, zone: String) -> HealthMeasurement {
        HealthMeasurement(
            id: UUID(), sleepStage: .asleepCore, startDate: date(start), endDate: date(end),
            source: .init(name: "Watch", bundleIdentifier: "fixture.watch"), timeZoneIdentifier: zone
        )
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func date(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_772_323_200 + Double(offset) * 86_400)
    }

    private func day(_ offset: Int) -> ManualLogDay { ManualLogDay(date(offset), timeZone: .gmt) }

    private func clock(_ name: String, starts: Int, in app: HealthAnalysisApplication) throws -> UUID {
        try app.manualLog.createTypedVariable(
            name: name, kind: .timeOfDay, defaultValue: time(23 * 60 + 30, precision: nil), startsOn: day(starts)
        ).id
    }

    private func time(_ minutes: Int, precision: ManualClockPrecision? = .exact) -> ManualTrackingValue {
        .timeOfDay(.init(hour: minutes / 60, minute: minutes % 60), precision: precision)
    }
}

private struct ClockSleepSource: HealthMeasurementSource {
    let records: [HealthMeasurement]

    func requestReadAccess() async throws {}

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        [.init(queryID: "sleep", anchor: Data([1]), added: records)]
    }
}

private struct ClockRandom {
    var state: UInt64 = 0x7ed681

    mutating func next() -> Double {
        state = state &* 2_862_933_555_777_941_757 &+ 3_037_000_493
        return Double(state >> 11) / 9_007_199_254_740_992
    }
}
