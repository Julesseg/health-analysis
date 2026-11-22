import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct ExploreAnalysisTests {
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
        #expect(result.observations.map(\.outputValue) == [62, 64, 65])
        #expect(result.observations.compactMap { $0.inputs.first?.value } == [100, 0, 75])
        #expect(result.observations[1].inputs.first?.origin == .observation)
        #expect(result.evidence.defaultDayCount == 1)
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
        #expect((0.88...0.99).contains(Double(independentCoverage) / Double(trials)))
        #expect((0.88...0.99).contains(Double(dependentCoverage) / Double(trials)))
        #expect(dependentWidth / independentWidth > 1.35)
        #expect((0.85...0.99).contains(Double(shortDependentCoverage) / Double(trials)))
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
        days: [(amount: Int?, bpm: Double?)], defaultAmount: Decimal = 0, changeDefaultAfterDays: Int? = nil
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
            output: .health(metric: .restingHeartRate), inputs: [.manualQuantity(caffeine.id)], timeZone: utc
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
