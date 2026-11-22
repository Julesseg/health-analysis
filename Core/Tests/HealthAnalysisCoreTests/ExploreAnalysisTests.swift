import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct ExploreAnalysisTests {
    @Test func completeWindowsKeepLookbackOutsideSelectedOutputHistory() async throws {
        let zone = try #require(TimeZone(identifier: "Europe/Paris"))
        let firstInput = instant("2025-03-02T12:00:00Z")
        let monthOutput = instant("2025-04-01T07:00:00Z")
        let endOfHistory = instant("2025-06-29T21:00:00Z")
        let app = HealthAnalysisApplication(healthSource: AnalysisHealthSource(records: [
            measurement(instant("2025-03-31T07:00:00Z"), value: 61),
            measurement(instant("2025-04-01T05:00:00Z"), value: 85, end: instant("2025-07-01T00:00:00Z")),
            measurement(monthOutput, value: 64)
        ]))
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 10, startsOn: ManualLogDay(firstInput, timeZone: zone)
        )
        for (day, amount) in [
            (firstInput, "30"), (instant("2025-03-26T12:00:00Z"), "20"),
            (instant("2025-03-30T12:00:00Z"), "0"), (monthOutput, "900")
        ] {
            app.manualLog.editQuantity(caffeine.id, on: ManualLogDay(day, timeZone: zone), text: amount, locale: locale)
        }
        await app.healthMeasurements.refresh()

        let week = try #require(AnalysisBehaviorWindow(rawValue: "precedingWeek"))
        let month = try #require(AnalysisBehaviorWindow(rawValue: "precedingMonth"))
        let recent = try #require(AnalysisPeriod(rawValue: "last90Days"))
        var question = AnalysisConfiguration(
            output: .health(metric: .restingHeartRate), inputs: [.manualQuantity(caffeine.id)], timeZone: zone
        )
        let dayResult = try app.analyze(question, asOf: endOfHistory)
        #expect(dayResult.observations.map { $0.inputs[0].value } == [0, 10])

        question.behaviorWindow = week
        let weekResult = try app.analyze(question, asOf: endOfHistory)
        #expect(weekResult.observations.map { $0.inputs[0].value } == [70, 70])

        question.behaviorWindow = month
        let full = try app.analyze(question, asOf: endOfHistory)
        #expect(full.coverage.outputDaysWithoutCompleteInput == 1)
        #expect(full.inspection?.unpairedOutputs.map(\.value) == [61])
        #expect(full.observations.map(\.outputAnchor) == [monthOutput])
        #expect(full.observations.map { $0.inputs[0].value } == [320])

        question.history = recent
        let selected = try app.analyze(question, asOf: endOfHistory)
        #expect(selected.coverage.outputDaysWithoutCompleteInput == 0)
        #expect(selected.inspection?.unpairedOutputs.isEmpty == true)
        #expect(selected.coverage.usableDates == [instant("2025-03-31T22:00:00Z")])
        #expect(selected.observations.map { $0.inputs[0].value } == [320])

        question.behaviorWindow = .precedingDay
        question.history = .last365Days
        let annual = try app.analyze(question, asOf: instant("2026-03-31T12:00:00Z"))
        #expect(annual.coverage.usableDates == [instant("2025-03-31T22:00:00Z")])
        let noRecentOutputs = try app.analyze(question, asOf: instant("2026-04-01T12:00:00Z"))
        #expect(noRecentOutputs.coverage.outputDayCount == 0)
        #expect(noRecentOutputs.coverage.firstDate == nil)
    }

    @Test func fullHistoryStartsAtFirstJointDayAndUsesTheCompleteCivilDayBeforeSampleStart() async throws {
        let zone = try #require(TimeZone(identifier: "Europe/Paris"))
        let early = instant("2025-03-29T10:00:00Z")
        let springDay = instant("2025-03-30T11:00:00Z")
        let nextDay = instant("2025-03-31T11:00:00Z")
        let later = instant("2025-04-02T11:00:00Z")
        let spanStart = instant("2025-03-30T21:30:00Z")
        let spanEnd = instant("2025-03-30T22:30:00Z")
        let records = [
            measurement(early, value: 90),
            measurement(spanStart, value: 62, end: spanEnd),
            measurement(spanStart.addingTimeInterval(60), value: 80),
            measurement(nextDay, value: 64),
            measurement(later, value: 65)
        ]
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appending(path: "health.json")
        let logURL = directory.appending(path: "log.json")
        let app = HealthAnalysisApplication(
            healthSource: AnalysisHealthSource(records: records),
            healthHistoryStoreURL: historyURL,
            manualLogStoreURL: logURL
        )
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 75,
            startsOn: ManualLogDay(early, timeZone: zone)
        )
        for (date, amount) in [(early, "100"), (springDay, "0"), (nextDay, "900")] {
            app.manualLog.editQuantity(caffeine.id, on: ManualLogDay(date, timeZone: zone), text: amount, locale: locale)
        }
        let reviewedDay = ManualLogDay(instant("2025-04-01T12:00:00Z"), timeZone: zone)
        try app.manualLog.confirmDay(reviewedDay)
        try app.manualLog.setQuantityDefault(caffeine.id, value: 125, effectiveOn: reviewedDay)
        await app.healthMeasurements.refresh()

        let reopened = HealthAnalysisApplication(healthHistoryStoreURL: historyURL, manualLogStoreURL: logURL)
        let result = try reopened.analyze(.init(
            output: .health(metric: .restingHeartRate),
            inputs: [.manualQuantity(caffeine.id)],
            timeZone: zone
        ))

        #expect(result.coverage.usableDates == [
            instant("2025-03-29T23:00:00Z"), instant("2025-03-30T22:00:00Z"), instant("2025-04-01T22:00:00Z")
        ])
        #expect(result.coverage.gaps.map(\.firstDate) == [instant("2025-03-31T22:00:00Z")])
        #expect(result.coverage.outputDaysWithoutCompleteInput == 1)
        let unpaired = try #require(result.inspection?.unpairedOutputs.first)
        #expect(result.inspection?.unpairedOutputs.count == 1)
        #expect(unpaired.date == instant("2025-03-28T23:00:00Z"))
        #expect(unpaired.anchor == early)
        #expect(unpaired.value == 90)
        #expect(unpaired.missingInputs.map(\.series) == [.manualQuantity(caffeine.id)])
        #expect(unpaired.missingInputs.map(\.date) == [instant("2025-03-27T23:00:00Z")])
        #expect(result.observations.map(\.outputValue) == [62, 64, 65])
        #expect(result.observations.compactMap { $0.inputs.first?.value } == [100, 0, 75])
        #expect(result.observations[1].inputs.first?.origin == .observation)
        #expect(result.evidence.defaultDayCount == 1)
        let input = result.inputEvidence(for: .manualQuantity(caffeine.id))
        #expect(input.explicitCount == 2)
        #expect(input.assumedDefaultCount == 1)
        #expect(input.approximateCount == nil)
        #expect(input.observedPairs.map(\.input.value) == [100, 0])
        #expect(input.observedPairs.map(\.outputValue) == [62, 64])
        #expect(result.coverage.distinctBehaviorDayCount == 3)
        #expect(result.coverage.nonOverlappingWindowCount == 3)

        let resultData = try JSONEncoder().encode(result)
        var earlierPayload = try #require(JSONSerialization.jsonObject(with: resultData) as? [String: Any])
        earlierPayload.removeValue(forKey: "inspection")
        var earlierCoverage = try #require(earlierPayload["coverage"] as? [String: Any])
        for key in ["distinctBehaviorDayCount", "nonOverlappingWindowCount", "outputDatesWithoutCompleteInput"] {
            earlierCoverage.removeValue(forKey: key)
        }
        earlierPayload["coverage"] = earlierCoverage
        var earlierObservations = try #require(earlierPayload["observations"] as? [[String: Any]])
        for index in earlierObservations.indices {
            var inputs = try #require(earlierObservations[index]["inputs"] as? [[String: Any]])
            for input in inputs.indices { inputs[input].removeValue(forKey: "days") }
            earlierObservations[index]["inputs"] = inputs
        }
        earlierPayload["observations"] = earlierObservations
        let earlierData = try JSONSerialization.data(withJSONObject: earlierPayload)
        let earlierResult = try JSONDecoder().decode(AnalysisResult.self, from: earlierData)
        #expect(earlierResult.inspection == nil)
        #expect(earlierResult.coverage.outputDaysWithoutCompleteInput == 1)
        #expect(earlierResult.coverage.distinctBehaviorDayCount == 3)
        #expect(earlierResult.inputEvidence(for: .manualQuantity(caffeine.id)).observedPairs.map(\.outputValue) == [62, 64])
    }

    @Test func coverageCountsCivilDaysWhenDaylightSavingStartsAtMidnight() async throws {
        let zone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let firstOutput = instant("2018-11-04T03:30:00Z")
        let secondOutput = instant("2018-11-06T02:30:00Z")
        let app = HealthAnalysisApplication(healthSource: AnalysisHealthSource(records: [
            measurement(firstOutput, value: 61), measurement(secondOutput, value: 64)
        ]))
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 50,
            startsOn: ManualLogDay(instant("2018-11-03T12:00:00Z"), timeZone: zone)
        )
        await app.healthMeasurements.refresh()

        let result = try app.analyze(.init(
            output: .health(metric: .restingHeartRate), inputs: [.manualQuantity(caffeine.id)], timeZone: zone
        ))
        let gap = try #require(result.coverage.gaps.first)
        #expect(result.coverage.missingDays == 1)
        #expect(gap.firstDate == instant("2018-11-05T02:00:00Z"))
        #expect(gap.lastDate == gap.firstDate)
    }

    @Test func coverageSeparatesSharedInputDaysFromOutputGapsAndIncompleteWindows() async throws {
        let first = instant("2025-01-01T00:00:00Z")
        func day(_ offset: Int) -> Date { first.addingTimeInterval(Double(offset) * 86_400) }
        let app = HealthAnalysisApplication(healthSource: AnalysisHealthSource(records: [
            measurement(day(6), value: 61), measurement(day(7), value: 62),
            measurement(day(8), value: 63), measurement(day(14), value: 64)
        ]))
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 25, startsOn: ManualLogDay(first, timeZone: utc)
        )
        app.manualLog.editQuantity(caffeine.id, on: ManualLogDay(day(7), timeZone: utc), text: "0", locale: locale)
        await app.healthMeasurements.refresh()

        let result = try app.analyze(.init(
            output: .health(metric: .restingHeartRate), inputs: [.manualQuantity(caffeine.id)],
            behaviorWindow: .precedingWeek, timeZone: utc
        ), asOf: day(14))
        #expect(result.coverage.usableDates == [day(7), day(8), day(14)])
        #expect(result.coverage.outputDatesWithoutCompleteInput == [day(6)])
        #expect(result.coverage.outputDayCount == 4)
        #expect(result.coverage.missingDays == 5)
        #expect(result.coverage.distinctBehaviorDayCount == 14)
        #expect(result.coverage.nonOverlappingWindowCount == 2)
        #expect(result.inspection?.unpairedOutputs.first?.missingInputs.map(\.date) == [day(-1)])
        let provenance = result.inputEvidence(for: .manualQuantity(caffeine.id))
        #expect(provenance.distinctEntries.count == 14)
        #expect(provenance.distinctEntries.filter { $0.origin == .observation }.map(\.date) == [day(7)])
        #expect(provenance.observedPairs.isEmpty)
        let days = try #require(result.observations[1].inputs.first?.days)
        #expect(days.map(\.date) == (1...7).map(day))
        #expect(days.last?.origin == .observation)
        #expect(days.last?.value == 0)
    }

    @Test func sleepDurationUsesRecordedWakeDateButKeepsBehaviorBeforeEpisodeOnset() async throws {
        let start = instant("2025-03-31T08:00:00Z")
        let wake = instant("2025-03-31T16:00:00Z")
        func sleep(_ start: Date, _ end: Date) -> HealthMeasurement {
            HealthMeasurement(
                id: UUID(), sleepStage: .asleepUnspecified, startDate: start, endDate: end,
                source: .init(name: "Watch", bundleIdentifier: "fixture.watch"),
                timeZoneIdentifier: "Pacific/Kiritimati"
            )
        }
        let nap = instant("2025-03-31T20:00:00Z")
        let app = HealthAnalysisApplication(healthSource: AnalysisHealthSource(records: [
            sleep(start, wake), sleep(nap, nap.addingTimeInterval(3600)),
            sleep(instant("2025-04-01T08:00:00Z"), instant("2025-04-01T17:00:00Z"))
        ]))
        let firstInput = instant("2025-03-30T00:00:00Z")
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 0, startsOn: ManualLogDay(firstInput, timeZone: utc)
        )
        for (date, amount) in [(firstInput, "120"), (start, "900"), (instant("2025-04-01T08:00:00Z"), "700")] {
            app.manualLog.editQuantity(caffeine.id, on: ManualLogDay(date, timeZone: utc), text: amount, locale: locale)
        }
        await app.healthMeasurements.refresh()

        let result = try app.analyze(.init(
            output: .health(metric: .sleepAnalysis), inputs: [.manualQuantity(caffeine.id)], timeZone: utc
        ), asOf: instant("2025-04-01T12:00:00Z"))
        #expect(result.coverage.usableDates == [instant("2025-04-01T00:00:00Z")])
        #expect(result.observations.map(\.outputAnchor) == [wake])
        #expect(result.observations.map(\.outputValue) == [8])
        #expect(result.observations.map { $0.inputs[0].date } == [firstInput])
        #expect(result.observations.map { $0.inputs[0].value } == [120])
    }

    @Test func unfinishedSleepRecordsCannotReviseAnEarlierAnalysis() async throws {
        let start = instant("2025-03-29T22:00:00Z")
        let wake = instant("2025-03-30T06:00:00Z")
        let awakeStart = instant("2025-03-30T05:00:00Z")
        let awakeEnd = instant("2025-03-30T08:00:00Z")
        let source = HealthMeasurement.Source(name: "Watch", bundleIdentifier: "fixture.watch")
        let app = HealthAnalysisApplication(healthSource: AnalysisHealthSource(records: [
            .init(id: UUID(), sleepStage: .asleepUnspecified, startDate: start, endDate: wake,
                  source: source, timeZoneIdentifier: "UTC"),
            .init(id: UUID(), sleepStage: .awake, startDate: awakeStart, endDate: awakeEnd,
                  source: source, timeZoneIdentifier: "UTC")
        ]))
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 0,
            startsOn: ManualLogDay(instant("2025-03-28T00:00:00Z"), timeZone: utc)
        )
        await app.healthMeasurements.refresh()
        let question = AnalysisConfiguration(
            output: .health(metric: .sleepAnalysis), inputs: [.manualQuantity(caffeine.id)], timeZone: utc
        )
        let earlier = try app.analyze(question, asOf: instant("2025-03-30T07:00:00Z"))
        #expect(earlier.observations.map(\.outputAnchor) == [wake])
        #expect(earlier.observations.map(\.outputValue) == [8])

        let later = try app.analyze(question, asOf: awakeEnd)
        #expect(later.observations.map(\.outputAnchor) == [awakeStart])
        #expect(later.observations.map(\.outputValue) == [7])
    }

    @Test func aSkippedCivilDateCreatesNeitherAnInputRequirementNorAnOutputGap() async throws {
        let zone = try #require(TimeZone(identifier: "Pacific/Apia"))
        let firstInput = instant("2011-12-28T11:00:00Z")
        let firstOutput = instant("2011-12-29T11:00:00Z")
        let laterOutput = instant("2011-12-30T11:00:00Z")
        let app = HealthAnalysisApplication(healthSource: AnalysisHealthSource(records: [
            measurement(firstOutput, value: 61), measurement(laterOutput, value: 64)
        ]))
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 25, startsOn: ManualLogDay(firstInput, timeZone: zone)
        )
        await app.healthMeasurements.refresh()

        let result = try app.analyze(.init(
            output: .health(metric: .restingHeartRate), inputs: [.manualQuantity(caffeine.id)], timeZone: zone
        ), asOf: laterOutput)
        #expect(result.coverage.usableDates.count == 2)
        #expect(result.coverage.missingDays == 0)
        #expect(result.observations.last?.inputs[0].date == instant("2011-12-29T10:00:00Z"))
    }

    @Test func estimatesKnownAssociationInBPMPer100Milligrams() async throws {
        let generated = syntheticHistory(slope: 2, noiseScale: 0.35)
        let (result, caffeine) = try await analyze(days: generated)

        let estimate = try #require(result.estimates.first)
        #expect(estimate.input == .manualQuantity(caffeine.id))
        #expect(estimate.inputIncrement == 100)
        #expect(abs(estimate.difference - 2) < 0.15)
        #expect(estimate.interval.upperBound - estimate.interval.lowerBound < 0.4)
        #expect(estimate.interval.lowerBound > 1)
        #expect(estimate.finding == .higher)
        #expect(result.evidence.grade == .moderate)
    }

    @Test func shortMonthlyHistoryCannotBorrowEvidenceFromSharedDays() async throws {
        let (result, _) = try await analyze(
            days: syntheticHistory(slope: 0, noiseScale: 0.35, days: 100), window: .precedingMonth
        )
        #expect(result.coverage.usableDates.count == 71)
        #expect(result.coverage.nonOverlappingWindowCount == 3)
        #expect(result.estimates.isEmpty)
        #expect(result.evidence.grade == .insufficient)
        #expect(result.evidence.reasons == [.limitedNonOverlappingWindows])
    }

    @Test func preciseNearZeroAndUncertainNullAreDifferentResults() async throws {
        let (precise, _) = try await analyze(days: syntheticHistory(slope: 0, noiseScale: 0.35))
        let preciseEstimate = try #require(precise.estimates.first)
        #expect(abs(preciseEstimate.difference) < 0.15)
        #expect(preciseEstimate.interval.lowerBound > -1)
        #expect(preciseEstimate.interval.upperBound < 1)
        #expect(preciseEstimate.finding == .nearZero)
        #expect(precise.evidence.grade == .moderate)

        let (uncertain, _) = try await analyze(days: syntheticHistory(slope: 0, noiseScale: 12, seed: 17))
        let uncertainEstimate = try #require(uncertain.estimates.first)
        #expect(uncertainEstimate.interval.contains(0))
        #expect(uncertainEstimate.interval.upperBound - uncertainEstimate.interval.lowerBound > 2)
        #expect(uncertainEstimate.finding == .uncertain)
        #expect(uncertain.evidence.grade == .low)
        #expect(uncertain.evidence.reasons.contains(.wideInterval))
    }

    @Test func intervalsCoverKnownCoefficientsUnderSerialDependenceAndGaps() async throws {
        let trials = 144
        var independentCoverage = 0
        var dependentCoverage = 0
        var independentWidth = 0.0
        var dependentWidth = 0.0
        var shortDependentCoverage = 0
        for trial in 0..<trials {
            let slope = trial.isMultiple(of: 2) ? 0.0 : -1.5
            let seed = UInt64(1_000 + trial)
            let (independent, _) = try await analyze(days: syntheticHistory(
                slope: slope, noiseScale: 3, days: 252, seed: seed, withGaps: true
            ))
            let (dependent, _) = try await analyze(days: syntheticHistory(
                slope: slope, noiseScale: 3, days: 252, seed: seed, autoregression: 0.8, withGaps: true
            ))
            let (shortDependent, _) = try await analyze(days: syntheticHistory(
                slope: slope, noiseScale: 3, days: 52, seed: seed, autoregression: 0.8, withGaps: true
            ))
            let short = try #require(shortDependent.estimates.first?.interval)
            if short.contains(slope) { shortDependentCoverage += 1 }
            #expect(shortDependent.evidence.grade == .low)

            let iid = try #require(independent.estimates.first?.interval)
            let serial = try #require(dependent.estimates.first?.interval)
            if iid.contains(slope) { independentCoverage += 1 }
            if serial.contains(slope) { dependentCoverage += 1 }
            independentWidth += iid.upperBound - iid.lowerBound
            dependentWidth += serial.upperBound - serial.lowerBound
        }
        #expect((0.92...0.995).contains(Double(independentCoverage) / Double(trials)))
        #expect((0.92...0.995).contains(Double(dependentCoverage) / Double(trials)))
        #expect(dependentWidth / independentWidth > 1.35)
        #expect((0.92...0.995).contains(Double(shortDependentCoverage) / Double(trials)))
    }

    @Test func overlappingWindowIntervalsCoverNullAndKnownEffectsUnderDifferentDependence() async throws {
        let scenarios: [(AnalysisBehaviorWindow, Int, Double, Double, Int)] = [
            (.precedingWeek, 240, 0, 0, 1),
            (.precedingWeek, 240, 0.8, 0.8, 1),
            (.precedingMonth, 420, 0, 0, 1),
            (.precedingMonth, 420, 0, 0, 30),
            (.precedingMonth, 420, 0.9, 0.95, 1)
        ]
        let trials = 144
        var widths: [Double] = []
        for (window, length, predictorAR, residualAR, residualDays) in scenarios {
            var nullCoverage = 0
            var effectCoverage = 0
            var totalWidth = 0.0
            var totalError = 0.0
            for trial in 0..<trials {
                let null = trial.isMultiple(of: 2)
                let slope = null ? 0.0 : -1.5
                let history = syntheticWindowHistory(
                    slope: slope, windowDays: window.dayCount, length: length, seed: UInt64(43_000 + trial),
                    predictorAR: predictorAR, residualAR: residualAR, residualDays: residualDays
                )
                let (result, _) = try await analyze(days: history, window: window)
                let estimate = try #require(result.estimates.first)
                if estimate.interval.contains(slope) {
                    if null { nullCoverage += 1 } else { effectCoverage += 1 }
                }
                totalWidth += estimate.interval.upperBound - estimate.interval.lowerBound
                totalError += abs(estimate.difference - slope)
                #expect(result.evidence.grade == .low)
            }
            let scenario = Comment(rawValue: "\(window), predictor AR \(predictorAR), residual AR \(residualAR), residual window \(residualDays)")
            #expect((0.92...0.995).contains(Double(nullCoverage + effectCoverage) / Double(trials)), scenario)
            #expect(Double(min(nullCoverage, effectCoverage)) / Double(trials / 2) >= 0.88, scenario)
            #expect(totalError / Double(trials) < 0.5, scenario)
            #expect(totalWidth / Double(trials) < 2.5, scenario)
            widths.append(totalWidth / Double(trials))
        }
        #expect(widths[3] > 2 * widths[2])
    }

    @Test func defaultHeavyAndSparseHistoryReportsLimitationsWithExecutableEstimate() async throws {
        let days = syntheticHistory(slope: 0, noiseScale: 1).enumerated().map { index, pair in
            (amount: index.isMultiple(of: 2) ? nil : pair.amount,
             bpm: index.isMultiple(of: 3) ? nil : pair.bpm)
        }
        let (result, _) = try await analyze(days: days, defaultAmount: 100)

        #expect(!result.estimates.isEmpty)
        #expect(result.coverage.usableDates.count == 112)
        #expect(result.coverage.missingDays == 55)
        #expect(result.evidence.defaultDayCount == 56)
        #expect(result.evidence.grade == .low)
        #expect(result.evidence.reasons.contains(.manyDefaults))
        #expect(result.evidence.reasons.contains(.sparseCoverage))
    }

    @Test func changingDefaultsAloneCannotProduceAnEstimate() async throws {
        let days = syntheticHistory(slope: 0, noiseScale: 1).map { (amount: nil as Int?, bpm: $0.bpm) }
        let (result, _) = try await analyze(days: days, defaultAmount: 100, changeDefaultAfterDays: 84)

        #expect(result.coverage.usableDates.count == 168)
        #expect(result.evidence.defaultDayCount == 168)
        #expect(result.estimates.isEmpty)
        #expect(result.evidence.grade == .insufficient)
        #expect(result.evidence.reasons == [.noObservedInputs])
    }

    @Test func inadequateCoverageAndLowVariationBothWithholdEstimatesWithDifferentReasons() async throws {
        let fewDays = syntheticHistory(slope: 2, noiseScale: 1, days: 20)
        let (sparse, _) = try await analyze(days: fewDays)
        #expect(sparse.estimates.isEmpty)
        #expect(sparse.evidence.grade == .insufficient)
        #expect(sparse.evidence.reasons == [.inadequateCoverage])

        let nearlyConstant = syntheticHistory(slope: 0, noiseScale: 1).enumerated().map { index, pair in
            (amount: Optional(100 + index % 3), bpm: pair.bpm)
        }
        let (constant, _) = try await analyze(days: nearlyConstant)
        #expect(constant.estimates.isEmpty)
        #expect(constant.evidence.grade == .insufficient)
        #expect(constant.evidence.reasons == [.limitedInputVariation])
    }

    @Test func analysisUsesOnlyTheSelectedSourceAndMarksFailedReadsOfEarlierHistory() async throws {
        let day = instant("2025-01-01T09:00:00Z")
        let watch = HealthMeasurement.Source(name: "Watch", bundleIdentifier: "fixture.watch")
        let bridge = HealthMeasurement.Source(name: "Bridge", bundleIdentifier: "fixture.bridge")
        let records = [measurement(day, value: 60, source: watch), measurement(day, value: 90, source: bridge)]
        let app = HealthAnalysisApplication(healthSource: AnalysisHealthSource(records: records, failAfterImport: true))
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 75,
            startsOn: ManualLogDay(day.addingTimeInterval(-86_400), timeZone: utc)
        )
        let configuration = AnalysisConfiguration(
            output: .health(metric: .restingHeartRate), inputs: [.manualQuantity(caffeine.id)], timeZone: utc
        )
        await app.healthMeasurements.refresh()
        #expect(throws: AnalysisRunFailure.chooseOutputSource) { try app.analyze(configuration) }
        try app.healthMeasurements.setPreferredSource(watch.bundleIdentifier, for: .restingHeartRate)
        let before = try app.analyze(configuration)
        #expect(before.outputSource == watch)
        #expect(before.observations.map(\.outputValue) == [60])
        #expect(before.lastHealthReadFailure == nil)

        await app.healthMeasurements.refresh()
        let after = try app.analyze(configuration)
        #expect(after.outputSource == watch)
        #expect(after.observations.map(\.outputValue) == [60])
        #expect(after.lastHealthReadFailure == .protectedData)
        #expect(after.healthHistoryReadAt == before.healthHistoryReadAt)

        var selectedBridge = configuration
        selectedBridge.output = .health(metric: .restingHeartRate, sourceBundleIdentifier: bridge.bundleIdentifier)
        let other = try app.analyze(selectedBridge)
        #expect(other.outputSource == bridge)
        #expect(other.observations.map(\.outputValue) == [90])

        let unavailable = HealthAnalysisApplication()
        _ = try unavailable.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 0, startsOn: ManualLogDay(day, timeZone: utc)
        )
        let missing = try #require(unavailable.analysisCaffeineQuantities.first)
        var missingHistory = configuration
        missingHistory.inputs = [.manualQuantity(missing.id)]
        #expect(try unavailable.analyze(missingHistory).evidence.reasons == [.inadequateCoverage])
        await unavailable.healthMeasurements.refresh()
        #expect(throws: AnalysisRunFailure.healthHistoryUnavailable(.unavailable)) {
            try unavailable.analyze(missingHistory)
        }
    }

    private let utc = TimeZone(secondsFromGMT: 0)!

    private func analyze(
        days: [(amount: Int?, bpm: Double?)], defaultAmount: Decimal = 0, changeDefaultAfterDays: Int? = nil,
        window: AnalysisBehaviorWindow = .precedingDay
    ) async throws -> (AnalysisResult, TrackingQuantity) {
        let firstDay = Date(timeIntervalSince1970: 1_735_689_600)
        func date(_ index: Int) -> Date {
            firstDay.addingTimeInterval(Double(index) * 86_400)
        }
        let records = days.enumerated().compactMap { index, pair in
            pair.bpm.map { measurement(date(index + 1).addingTimeInterval(32_400), value: $0) }
        }
        let app = HealthAnalysisApplication(healthSource: AnalysisHealthSource(records: records))
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: defaultAmount,
            startsOn: ManualLogDay(firstDay, timeZone: utc)
        )
        if let changeDefaultAfterDays {
            try app.manualLog.setQuantityDefault(
                caffeine.id, value: defaultAmount + 100,
                effectiveOn: ManualLogDay(date(changeDefaultAfterDays), timeZone: utc)
            )
        }
        for (index, pair) in days.enumerated() {
            if let amount = pair.amount {
                app.manualLog.editQuantity(
                    caffeine.id, on: ManualLogDay(date(index), timeZone: utc), text: String(amount), locale: locale
                )
            }
        }
        await app.healthMeasurements.refresh()
        return (try app.analyze(.init(
            output: .health(metric: .restingHeartRate), inputs: [.manualQuantity(caffeine.id)],
            behaviorWindow: window, timeZone: utc
        ), asOf: date(days.count + 1)), caffeine)
    }

    private func syntheticHistory(
        slope: Double, noiseScale: Double, days: Int = 168, seed: UInt64 = 82,
        autoregression: Double = 0, withGaps: Bool = false
    ) -> [(amount: Int?, bpm: Double?)] {
        var random = GaussianSequence(seed: seed)
        let innovationScale = sqrt(1 - autoregression * autoregression)
        var predictor = random.next()
        var noise = random.next()
        return (0..<days).map { index in
            predictor = autoregression * predictor + innovationScale * random.next()
            noise = autoregression * noise + innovationScale * random.next()
            let amount = max(0, Int((220 + 60 * predictor).rounded()))
            let bpm = 65 + slope * Double(amount - 220) / 100 + noiseScale * noise
            return (amount, withGaps && (index % 17 >= 14) ? nil : bpm)
        }
    }

    private func syntheticWindowHistory(
        slope: Double, windowDays: Int, length: Int, seed: UInt64,
        predictorAR: Double, residualAR: Double, residualDays: Int
    ) -> [(amount: Int?, bpm: Double?)] {
        var random = GaussianSequence(seed: seed)
        var predictor = 0.0
        var residual = 0.0
        let predictorScale = sqrt(1 - predictorAR * predictorAR)
        let residualScale = sqrt(1 - residualAR * residualAR)
        let warmup = 100
        var amounts: [Int] = []
        var errors: [Double] = []
        for _ in 0..<(length + warmup) {
            predictor = predictorAR * predictor + predictorScale * random.next()
            residual = residualAR * residual + residualScale * random.next()
            amounts.append(max(0, Int((220 + 60 * predictor).rounded())))
            errors.append(residual)
        }
        return (warmup..<(length + warmup)).map { index in
            let caffeine = amounts[(index + 1 - windowDays)...index].reduce(0, +) - 220 * windowDays
            let error = errors[(index + 1 - residualDays)...index].reduce(0, +) / sqrt(Double(residualDays))
            let bpm = 65 + slope * Double(caffeine) / 100 + 3 * error
            return (amounts[index], (index - warmup) % 17 >= 14 ? nil : bpm)
        }
    }

    private let locale = Locale(identifier: "en_US")

    private func instant(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }

    private func measurement(
        _ start: Date, value: Double, end: Date? = nil,
        source: HealthMeasurement.Source = .init(name: "Watch", bundleIdentifier: "fixture.watch")
    ) -> HealthMeasurement {
        .init(
            id: UUID(), metric: .restingHeartRate, value: value, unit: .beatsPerMinute,
            startDate: start, endDate: end ?? start, source: source
        )
    }
}

private struct AnalysisHealthSource: HealthMeasurementSource {
    let records: [HealthMeasurement]
    var failAfterImport = false

    func requestReadAccess() async throws {}

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        if failAfterImport && !anchors.isEmpty { throw HealthMeasurementReadFailure.protectedData }
        return [.init(queryID: "restingHeartRate", anchor: Data([1]), added: records)]
    }
}

private struct GaussianSequence {
    var seed: UInt64

    mutating func next() -> Double {
        sqrt(-2 * log(uniform())) * cos(2 * .pi * uniform())
    }

    private mutating func uniform() -> Double {
        seed &+= 0x9E3779B97F4A7C15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return (Double((value ^ (value >> 31)) >> 11) + 0.5) / 9_007_199_254_740_992
    }
}
