import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct CountAnalysisTests {
    @Test func reopenedCountQuestionPreservesZerosAndEffectiveDefaultsOnBothSides() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appending(path: "log.json")
        let savedURL = directory.appending(path: "analyses.json")
        let app = HealthAnalysisApplication(manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL)
        let input = try count("Coffees", in: app, starting: 1)
        let output = try count("Headaches", in: app, starting: 0)
        let option = TrackingCategory(name: "Home")
        let category = try app.manualLog.createTypedVariable(
            name: "Location", kind: .category([option, TrackingCategory(name: "Away")]),
            defaultValue: .category(option.id), startsOn: day(0)
        )
        app.manualLog.editTypedEntry(input.id, on: day(1), value: .count(0))
        app.manualLog.editTypedEntry(output.id, on: day(1), value: .count(7))
        app.manualLog.editTypedEntry(output.id, on: day(2), value: .count(0))
        try app.manualLog.confirmDay(day(3))
        try app.manualLog.setTypedDefault(input.id, value: .count(4), effectiveOn: day(2))
        try app.manualLog.setTypedDefault(output.id, value: .count(2), effectiveOn: day(2))
        app.manualLog.editTypedEntry(input.id, on: day(2), value: .count(4))
        app.manualLog.editTypedEntry(output.id, on: day(4), value: .count(5))
        app.manualLog.editTypedEntry(output.id, on: day(5), value: .count(6))
        let configuration = AnalysisConfiguration(
            output: .manualTyped(output.id), inputs: [.manualTyped(input.id)], timeZone: utc
        )

        let reopened = HealthAnalysisApplication(manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL)
        let catalog = reopened.analysisVariables
        let choice = try #require(catalog.first { $0.id == configuration.output })
        #expect(choice.kind == .tracked(.count))
        #expect(choice.supportsInput && choice.supportsOutput)
        let unsupported = try #require(catalog.first { $0.id == .manualTyped(category.id) })
        #expect(!unsupported.supportsInput && !unsupported.supportsOutput)

        let result = try reopened.analyze(configuration, asOf: date(5))
        #expect(result.coverage.usableDates == [date(2), date(3), date(4)])
        #expect(result.coverage.outputDaysWithoutCompleteInput == 2)
        #expect(result.observations.map(\.outputValue) == [0, 0, 5])
        #expect(result.observations.map(\.outputTrackingValue) == [.count(0), .count(0), .count(5)])
        #expect(result.observations.map(\.outputOrigin) == [
            .observation, .assumedDefault(effectiveOn: day(0)), .observation
        ])
        #expect(result.observations.compactMap { $0.inputs.first?.value } == [0, 4, 0])
        #expect(result.observations.compactMap { $0.inputs.first?.trackingValue } == [.count(0), .count(4), .count(0)])
        #expect(result.observations.compactMap { $0.inputs.first?.origin } == [
            .observation, .observation, .assumedDefault(effectiveOn: day(1))
        ])
        #expect(result.inputEvidence(for: configuration.inputs[0]).observedPairs.map(\.outputDate) == [date(2)])
        let observed = result.outputEvidence.filter(\.isObserved)
        #expect(observed.map(\.date) == [date(1), date(2), date(4)])
        #expect(observed.map(\.trackingValue) == [.count(7), .count(0), .count(5)])
        #expect(observed.map(\.paired) == [false, true, true])
        #expect(observed.allSatisfy { $0.source == nil && $0.origin == .observation })
        #expect(result.evidence.defaultDayCount == 2)
        #expect(result.healthHistoryReadAt == nil)

        let completion = try #require(await reopened.refreshAnalysis(configuration)).get()
        let saved = try reopened.savedAnalyses.save(configuration, completed: completion)
        let again = HealthAnalysisApplication(manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL)
        #expect(again.savedAnalyses.state(for: saved.id).completed?.result.observations.first?.outputTrackingValue == .count(0))
        #expect(again.savedAnalyses.state(for: saved.id).completed?.result.outputEvidence.filter(\.isObserved).map(\.date)
            == [date(1), date(2), date(4), date(5)])
        await again.refreshSavedAnalysis(saved.id)
        #expect(again.savedAnalyses.state(for: saved.id).failure == nil)
        #expect(again.savedAnalyses.state(for: saved.id).completed?.result.configuration == configuration)
        #expect(again.savedAnalyses.state(for: saved.id).completed?.result.observations.first?.outputOrigin == .observation)
    }

    @Test func jointCountModelRecoversKnownMultiplicativeAssociationsIncludingZerosAfterReopeningLog() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appending(path: "log.json")
        let app = HealthAnalysisApplication(manualLogStoreURL: logURL)
        let input = try count("Coffees", in: app)
        let adjustment = try count("Late shifts", in: app)
        let output = try count("Headaches", in: app, starting: 1)
        for index in 0..<120 {
            let x = index % 2
            let z = index / 2 % 2
            let expected = (1 + x) * (1 + 2 * z)
            app.manualLog.editTypedEntry(input.id, on: day(index), value: .count(x))
            app.manualLog.editTypedEntry(adjustment.id, on: day(index), value: .count(z))
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .count(expected + index / 4 % 3 - 1))
        }
        let reopened = HealthAnalysisApplication(manualLogStoreURL: logURL)
        var configuration = AnalysisConfiguration(
            output: .manualTyped(output.id), inputs: [.manualTyped(input.id)],
            adjustmentInputs: [.manualTyped(adjustment.id)], timeZone: utc
        )
        let result = try reopened.analyze(configuration, asOf: date(121))

        #expect(result.model == .countLogLinearV1)
        #expect(result.observations.count == 120)
        #expect(result.observations.count { $0.outputValue == 0 } == 10)
        #expect(result.modeledInputs.map(\.role) == [.input, .adjustment])
        #expect(result.estimates.count == 2)
        for (estimate, increase) in zip(result.estimates, [1.0, 2.0]) {
            #expect(estimate.inputIncrement == 1)
            #expect(estimate.scale == .proportionalCountChange)
            #expect(abs(estimate.difference - increase) < 0.01)
            #expect(estimate.interval.contains(increase))
            #expect(estimate.interval.lowerBound > 0)
            #expect(estimate.finding == .higher)
        }
        #expect(result.evidence.grade == .low)
        #expect(result.evidence.dependenceLagDays == 10)

        configuration.history = .last90Days
        let shortened = try reopened.analyze(configuration, asOf: date(121))
        #expect(shortened.coverage.firstDate == date(32))
        #expect(shortened.coverage.lastDate == date(120))
        #expect(shortened.estimates.count == 2)
        configuration.behaviorWindow = .precedingWeek
        #expect(throws: AnalysisRunFailure.countWindowUnavailable) {
            try reopened.analyze(configuration, asOf: date(121))
        }
    }

    @Test func defaultsConstantCountsAndSeparatedGroupsWithholdAnEstimate() throws {
        let app = HealthAnalysisApplication()
        let input = try count("Coffees", in: app)
        let output = try count("Headaches", in: app, starting: 1)
        let configuration = AnalysisConfiguration(
            output: .manualTyped(output.id), inputs: [.manualTyped(input.id)], timeZone: utc
        )
        for index in 0..<84 {
            app.manualLog.editTypedEntry(input.id, on: day(index), value: .count(index % 2))
        }
        try app.manualLog.setTypedDefault(output.id, value: .count(3), effectiveOn: day(43))
        let defaults = try app.analyze(configuration, asOf: date(85))
        #expect(defaults.evidence.reasons == [.defaultOnlyOutput])
        #expect(defaults.estimates.isEmpty)

        for index in 0..<84 {
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .count(0))
        }
        let zeros = try app.analyze(configuration, asOf: date(85))
        #expect(zeros.evidence.reasons == [.lowVariationOutput])
        #expect(zeros.estimates.isEmpty)
        #expect(zeros.evidence.defaultDayCount == 0)

        for index in stride(from: 1, to: 84, by: 2) {
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .count(1 + index % 5))
        }
        let separated = try app.analyze(configuration, asOf: date(85))
        #expect(separated.evidence.reasons == [.countModelUnavailable])
        #expect(separated.estimates.isEmpty)
    }

    @Test func countFitWithNoResidualVariationCannotReportAnUncertaintyInterval() throws {
        let app = HealthAnalysisApplication()
        let input = try count("Coffees", in: app)
        let output = try count("Headaches", in: app, starting: 1)
        for index in 0..<70 {
            let count = index % 2
            app.manualLog.editTypedEntry(input.id, on: day(index), value: .count(count))
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .count(1 + count))
        }
        let result = try app.analyze(.init(
            output: .manualTyped(output.id), inputs: [.manualTyped(input.id)], timeZone: utc
        ), asOf: date(71))
        #expect(result.evidence.reasons == [.uncertaintyUnavailable])
        #expect(result.estimates.isEmpty)
    }

    @Test func countInputEstimatesBPMPerEventWithRecordedZerosAndSparseNonzeros() async throws {
        let source = HealthMeasurement.Source(name: "Synthetic watch", bundleIdentifier: "fixture.count")
        let records = (0..<120).compactMap { index -> HealthMeasurement? in
            guard index / 6 % 9 != 2 else { return nil }
            let time = date(index + 1).addingTimeInterval(32_400)
            let bpm = 60 + Double(index.isMultiple(of: 6) ? 2 : 0) + Double(index / 6 % 3 - 1) * 0.2
            return HealthMeasurement(
                id: UUID(), metric: .restingHeartRate, value: bpm, unit: .beatsPerMinute,
                startDate: time, endDate: time, source: source
            )
        }
        let app = HealthAnalysisApplication(healthSource: CountTestHealthSource(records: records))
        let count = try count("Coffees", in: app)
        for index in 0..<120 {
            app.manualLog.editTypedEntry(count.id, on: day(index), value: .count(index.isMultiple(of: 6) ? 1 : 0))
        }
        let configuration = AnalysisConfiguration(
            output: .health(metric: .restingHeartRate), inputs: [.manualTyped(count.id)], timeZone: utc
        )
        let completed = try #require(await app.refreshAnalysis(configuration)).get()
        let result = completed.result
        let estimate = try #require(result.estimates.first)
        #expect(estimate.scale == .difference)
        #expect(estimate.inputIncrement == 1)
        #expect(abs(estimate.difference - 2) < 0.03)
        #expect(estimate.interval.contains(2))
        #expect(result.outputSource == source)
        #expect(result.coverage.missingDays == 12)
        #expect(result.evidence.defaultDayCount == 0)
        #expect(result.observations.filter { $0.inputs[0].trackingValue == .count(0) }.count == 90)
    }

    @Test func countIntervalsTrackKnownNullAndNonNullMeansWithSerialOverdispersion() throws {
        let trials = 72
        var coverage = [0, 0]
        var width = [0.0, 0.0]
        var bias = [0.0, 0.0]
        for trial in 0..<trials {
            let ratio = trial.isMultiple(of: 2) ? 1.0 : 1.45
            for (scenario, persistence) in [0.0, 0.8].enumerated() {
                let app = HealthAnalysisApplication()
                let input = try count("Coffees", in: app)
                let output = try count("Headaches", in: app, starting: 1)
                var random = CountRandom(state: UInt64(trial + 7_200))
                var countRandom = CountRandom(state: UInt64(trial + 934_000))
                var state = random.uniform() < 0.5 ? -1.0 : 1.0
                var x = 0
                for index in 0..<336 {
                    if index.isMultiple(of: 7) { x = Int(random.uniform() * 3) }
                    if random.uniform() < (1 - persistence) / 2 { state = -state }
                    let mean = 2 * pow(ratio, Double(x)) * (1 + 0.65 * state)
                    app.manualLog.editTypedEntry(input.id, on: day(index), value: .count(x))
                    app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .count(countRandom.poisson(mean)))
                }
                let result = try app.analyze(.init(
                    output: .manualTyped(output.id), inputs: [.manualTyped(input.id)], timeZone: utc
                ), asOf: date(337))
                let estimate = try #require(result.estimates.first)
                let expected = ratio - 1
                if estimate.interval.contains(expected) { coverage[scenario] += 1 }
                width[scenario] += estimate.interval.upperBound - estimate.interval.lowerBound
                bias[scenario] += estimate.difference - expected
                #expect(result.evidence.grade == .low)
            }
        }
        #expect((0.87...1).contains(Double(coverage[0]) / Double(trials)))
        #expect((0.85...1).contains(Double(coverage[1]) / Double(trials)))
        #expect(width[1] / width[0] > 1.2)
        #expect(abs(bias[0] / Double(trials)) < 0.05)
        #expect(abs(bias[1] / Double(trials)) < 0.05)
    }

    @Test func countAdjustmentCannotSilentlyReuseAQuantityInteractionModel() throws {
        let app = HealthAnalysisApplication()
        let focal = try app.manualLog.createQuantity(name: "Caffeine", unit: "mg", defaultValue: 0, startsOn: day(0))
        let moderator = try app.manualLog.createQuantity(name: "Exercise", unit: "min", defaultValue: 0, startsOn: day(0))
        let count = try count("Coffees", in: app)
        let configuration = AnalysisConfiguration(
            output: .health(metric: .restingHeartRate), inputs: [.manualQuantity(focal.id), .manualQuantity(moderator.id)],
            adjustmentInputs: [.manualTyped(count.id)],
            interaction: .init(focal: .manualQuantity(focal.id), moderator: .manualQuantity(moderator.id)), timeZone: utc
        )
        #expect(throws: AnalysisRunFailure.countInteractionUnavailable) {
            try app.analyze(configuration, asOf: date(1))
        }
    }

    private let utc = TimeZone(secondsFromGMT: 0)!

    private func date(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_735_689_600 + Double(offset) * 86_400)
    }

    private func day(_ offset: Int) -> ManualLogDay {
        ManualLogDay(date(offset), timeZone: utc)
    }

    private func count(
        _ name: String, in app: HealthAnalysisApplication, starting offset: Int = 0
    ) throws -> TypedTrackingVariable {
        try app.manualLog.createTypedVariable(name: name, kind: .count, defaultValue: .count(0), startsOn: day(offset))
    }
}

private struct CountRandom {
    var state: UInt64

    mutating func uniform() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / 9_007_199_254_740_992
    }

    mutating func poisson(_ mean: Double) -> Int {
        let threshold = exp(-mean)
        var product = uniform()
        var count = 0
        while product > threshold {
            count += 1
            product *= uniform()
        }
        return count
    }
}

private struct CountTestHealthSource: HealthMeasurementSource {
    let records: [HealthMeasurement]

    func requestReadAccess() async throws {}

    func readChanges(
        after anchors: [String: Data], includingPreviouslySaved: Bool
    ) async throws -> [HealthMeasurementChanges] {
        [.init(queryID: "restingHeartRate", anchor: Data([1]), added: records)]
    }
}
