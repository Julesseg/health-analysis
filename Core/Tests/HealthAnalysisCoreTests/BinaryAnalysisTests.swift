import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct BinaryAnalysisTests {
    @Test func binaryQuestionReportsAnAdjustedProbabilityDifferenceForYesVersusNo() throws {
        let app = HealthAnalysisApplication()
        let input = try binary("Late meal", in: app)
        let adjustment = try binary("Night shift", in: app)
        let output = try binary("Headache", in: app, starting: 1)
        // Night shifts are twice as common after a late meal. Within shifts, probabilities are 40% and two thirds.
        let totals = [120, 60, 60, 120]
        let yesCounts = [12, 15, 24, 80]
        let groups = [0, 3, 2, 0, 1, 3]
        var seen = [0, 0, 0, 0]
        for index in 0..<360 {
            let group = groups[index % groups.count]
            app.manualLog.editTypedEntry(input.id, on: day(index), value: .yesNo(group % 2 == 1))
            app.manualLog.editTypedEntry(adjustment.id, on: day(index), value: .yesNo(group >= 2))
            let rank = seen[group] * 17 % totals[group]
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .yesNo(rank < yesCounts[group]))
            seen[group] += 1
        }
        let configuration = AnalysisConfiguration(
            output: .manualTyped(output.id), inputs: [.manualTyped(input.id)],
            adjustmentInputs: [.manualTyped(adjustment.id)], timeZone: utc
        )
        let choice = try #require(app.analysisVariables.first { $0.id == configuration.output })
        #expect(choice.supportsInput && choice.supportsOutput)
        let result = try app.analyze(configuration, asOf: date(361))
        #expect(result.model == .binaryLogisticV1)
        #expect(result.modeledInputs.map(\.role) == [.input, .adjustment])
        #expect(result.observations.count == 360)
        #expect(result.evidence.grade == .low)
        #expect(result.evidence.dependenceLagDays == 15)
        let estimate = try #require(result.estimates.first)
        #expect(estimate.scale == .probabilityDifference)
        #expect(abs(estimate.difference - 0.2083333333) < 0.0001)
        #expect(estimate.interval.contains(0.2083333333))
        #expect(estimate.interval.lowerBound > 0)
        #expect((-1...1).contains(estimate.interval.lowerBound))
        #expect((-1...1).contains(estimate.interval.upperBound))
    }

    @Test func missingRecordedCombinationsWithholdAnOtherwiseEstimableBinaryResult() throws {
        let app = HealthAnalysisApplication()
        let input = try binary("Late meal", in: app)
        let adjustment = try binary("Night shift", in: app)
        let output = try binary("Headache", in: app, starting: 1)
        for index in 0..<120 {
            let group = index % 3
            app.manualLog.editTypedEntry(input.id, on: day(index), value: .yesNo(group == 1))
            app.manualLog.editTypedEntry(adjustment.id, on: day(index), value: .yesNo(group == 2))
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .yesNo(index / 3 % 5 <= group))
        }
        let inputIDs = [input, adjustment].map { AnalysisSeriesID.manualTyped($0.id) }
        let result = try app.analyze(.init(
            output: .manualTyped(output.id), inputs: [inputIDs[0]],
            adjustmentInputs: [inputIDs[1]], timeZone: utc
        ), asOf: date(121))
        #expect(result.evidence.grade == .insufficient)
        #expect(result.evidence.reasons == [.sparseBinaryCombinations(Set(inputIDs))])
        #expect(result.estimates.isEmpty)
    }

    @Test func storedBinaryValuesPreserveExplicitNoAndConfirmedDefaultAfterReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appending(path: "log.json")
        let savedURL = directory.appending(path: "analyses.json")
        let app = HealthAnalysisApplication(manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL)
        let input = try binary("Late meal", in: app, starting: 1)
        let output = try binary("Headache", in: app)
        app.manualLog.editTypedEntry(input.id, on: day(1), value: .yesNo(false))
        app.manualLog.editTypedEntry(output.id, on: day(2), value: .yesNo(false))
        try app.manualLog.confirmDay(day(3))
        try app.manualLog.setTypedDefault(output.id, value: .yesNo(true), effectiveOn: day(2))
        let configuration = AnalysisConfiguration(
            output: .manualTyped(output.id), inputs: [.manualTyped(input.id)], timeZone: utc
        )

        let reopened = HealthAnalysisApplication(manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL)
        let result = try reopened.analyze(configuration, asOf: date(4))
        #expect(result.coverage.usableDates == [date(2), date(3)])
        #expect(result.evidence.defaultDayCount == 1)
        #expect(result.healthHistoryReadAt == nil)
        #expect(result.outputEvidence.map(\.trackingValue) == [.yesNo(false), .yesNo(false), .yesNo(false), .yesNo(false)])
        #expect(result.outputEvidence.map(\.origin) == [
            .assumedDefault(effectiveOn: day(0)), .assumedDefault(effectiveOn: day(0)),
            .observation, .assumedDefault(effectiveOn: day(0))
        ])
        let evidence = result.inputEvidence(for: .manualTyped(input.id))
        #expect(evidence.explicitCount == 1)
        #expect(evidence.assumedDefaultCount == 1)
        #expect(evidence.observedPairs.first?.input.trackingValue == .yesNo(false))
        #expect(evidence.observedPairs.first?.outputTrackingValue == .yesNo(false))

        let completion = try #require(await reopened.refreshAnalysis(configuration)).get()
        let saved = try reopened.savedAnalyses.save(configuration, completed: completion)
        let again = HealthAnalysisApplication(manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL)
        await again.refreshSavedAnalysis(saved.id)
        let refreshed = try #require(again.savedAnalyses.state(for: saved.id).completed?.result)
        #expect(refreshed.model == .binaryLogisticV1)
        #expect(refreshed.observations.first?.outputTrackingValue == .yesNo(false))
        #expect(refreshed.observations.first?.outputOrigin == .observation)
        #expect(refreshed.healthHistoryReadAt == nil)
    }

    @Test func defaultOnlyConstantAndSparseRecordedOutputsHaveDistinctReasons() throws {
        let app = HealthAnalysisApplication()
        let input = try binary("Late meal", in: app)
        let output = try binary("Headache", in: app, starting: 1)
        let configuration = AnalysisConfiguration(
            output: .manualTyped(output.id), inputs: [.manualTyped(input.id)], timeZone: utc
        )
        for index in 0..<84 {
            app.manualLog.editTypedEntry(input.id, on: day(index), value: .yesNo(index.isMultiple(of: 2)))
        }
        try app.manualLog.setTypedDefault(output.id, value: .yesNo(true), effectiveOn: day(43))
        var result = try app.analyze(configuration, asOf: date(85))
        #expect(result.evidence.reasons == [.defaultOnlyOutput])
        #expect(result.estimates.isEmpty)

        for index in 0..<60 {
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .yesNo(false))
        }
        result = try app.analyze(configuration, asOf: date(85))
        #expect(result.evidence.reasons == [.lowVariationOutput])
        #expect(result.estimates.isEmpty)

        for index in 60..<65 {
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .yesNo(true))
        }
        result = try app.analyze(configuration, asOf: date(85))
        #expect(result.evidence.reasons == [.sparseObservedBinaryOutput])
        #expect(result.evidence.grade == .insufficient)
        #expect(result.estimates.isEmpty)
    }

    @Test func yesNoAdjustmentsUsePrecedingDaysAndExcludeInteractions() throws {
        let app = HealthAnalysisApplication()
        let input = try binary("Late meal", in: app)
        let first = try count("Coffee", in: app)
        let second = try count("Exercise", in: app)
        var configuration = AnalysisConfiguration(
            output: .health(metric: .restingHeartRate),
            inputs: [.manualTyped(first.id), .manualTyped(second.id)],
            adjustmentInputs: [.manualTyped(input.id)], timeZone: utc
        )
        configuration.behaviorWindow = .precedingWeek
        #expect(throws: AnalysisRunFailure.binaryWindowUnavailable) {
            try app.analyze(configuration, asOf: date(120))
        }
        configuration.behaviorWindow = .precedingDay
        configuration.interaction = .init(focal: configuration.inputs[0], moderator: configuration.inputs[1])
        #expect(throws: AnalysisRunFailure.binaryInteractionUnavailable) {
            try app.analyze(configuration, asOf: date(120))
        }
    }

    @Test func yesNoInputUsesAnAdjustedDifferenceForANumericOutput() async throws {
        let source = HealthMeasurement.Source(name: "Synthetic watch", bundleIdentifier: "fixture.binary")
        let records = (0..<120).map { index in
            let time = date(index + 1).addingTimeInterval(32_400)
            let input = index % 4 == 0 ? 1.0 : 0.0
            let adjustment = Double(index / 4 % 2)
            return HealthMeasurement(
                id: UUID(), metric: .restingHeartRate,
                value: 60 + 2 * input + 4 * adjustment + Double(index / 8 % 3 - 1) * 0.5,
                unit: .beatsPerMinute, startDate: time, endDate: time, source: source
            )
        }
        let app = HealthAnalysisApplication(healthSource: BinaryTestHealthSource(records: records))
        let input = try binary("Late meal", in: app)
        let adjustment = try count("Coffee", in: app)
        for index in 0..<120 {
            app.manualLog.editTypedEntry(input.id, on: day(index), value: .yesNo(index % 4 == 0))
            app.manualLog.editTypedEntry(adjustment.id, on: day(index), value: .count(index / 4 % 2))
        }
        let configuration = AnalysisConfiguration(
            output: .health(metric: .restingHeartRate), inputs: [.manualTyped(input.id)],
            adjustmentInputs: [.manualTyped(adjustment.id)], timeZone: utc
        )
        let result = try #require(await app.refreshAnalysis(configuration)).get().result
        let estimate = try #require(result.estimates.first)
        #expect(result.model == .numericLinearV1)
        #expect(estimate.scale == .difference)
        #expect(abs(estimate.difference - 2) < 0.03)
        #expect(estimate.interval.contains(2))
        #expect(result.coverage.usableDates.count == 120)
        #expect(result.observations.count { $0.inputs.first?.trackingValue == .yesNo(false) } == 90)
    }

    @Test func countInputUsesSupportedProbabilityIncrementsAndWithholdsASeparatedFit() throws {
        let app = HealthAnalysisApplication()
        let input = try count("Coffee", in: app)
        let output = try binary("Headache", in: app, starting: 1)
        let configuration = AnalysisConfiguration(
            output: .manualTyped(output.id), inputs: [.manualTyped(input.id)], timeZone: utc
        )
        for index in 0..<120 {
            let coffees = index % 2
            app.manualLog.editTypedEntry(input.id, on: day(index), value: .count(coffees))
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .yesNo(coffees == 1))
        }
        let separated = try app.analyze(configuration, asOf: date(121))
        #expect(separated.evidence.reasons == [.binaryModelUnavailable])
        #expect(separated.estimates.isEmpty)

        for index in 0..<120 {
            let yes = index / 2 * 17 % 60 < (index % 2 == 0 ? 12 : 30)
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .yesNo(yes))
        }
        let supported = try app.analyze(configuration, asOf: date(121))
        let estimate = try #require(supported.estimates.first)
        #expect(estimate.inputIncrement == 1)
        #expect(estimate.scale == .probabilityDifference)
        #expect(abs(estimate.difference - 0.3) < 0.0001)
        #expect(estimate.interval.contains(0.3))
    }

    @Test func assumedValuesCannotCreateSupportForANumericProbabilityContrast() throws {
        let app = HealthAnalysisApplication()
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 100, startsOn: day(0)
        )
        let output = try binary("Headache", in: app, starting: 1)
        for index in 0..<120 {
            if index % 3 != 2 {
                app.manualLog.editQuantity(
                    caffeine.id, on: day(index), text: index % 3 == 0 ? "0" : "50", locale: Locale(identifier: "en_US")
                )
            }
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .yesNo(index / 3 % 5 <= index % 3))
        }

        let inputID = AnalysisSeriesID.manualQuantity(caffeine.id)
        let result = try app.analyze(.init(
            output: .manualTyped(output.id), inputs: [inputID], timeZone: utc
        ), asOf: date(121))
        #expect(result.evidence.grade == .insufficient)
        #expect(result.evidence.reasons == [.binaryContrastUnavailable([inputID])])
        #expect(result.estimates.isEmpty)
        #expect(result.evidence.defaultDayCount == 40)
    }

    @Test func dependenceWidensBinaryIntervalsForKnownNullAndNonNullRiskDifferences() throws {
        let trials = 48
        var covered = [0, 0]
        var totalWidths = [0.0, 0.0]
        var totalErrors = [0.0, 0.0]
        for trial in 0..<trials {
            let difference = trial.isMultiple(of: 2) ? 0.0 : 0.18
            for (scenario, persistence) in [0.0, 0.8].enumerated() {
                let app = HealthAnalysisApplication()
                let input = try binary("Late meal", in: app)
                let output = try binary("Headache", in: app, starting: 1)
                var random = BinaryRandom(state: UInt64(trial + 840))
                var state = random.uniform() < 0.5 ? -1.0 : 1.0
                for index in 0..<336 {
                    let yes = index / 28 % 2 == 1
                    if random.uniform() < (1 - persistence) / 2 { state = -state }
                    let probability = 0.35 + (yes ? difference : 0) + 0.24 * state
                    app.manualLog.editTypedEntry(input.id, on: day(index), value: .yesNo(yes))
                    app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .yesNo(random.uniform() < probability))
                }
                let result = try app.analyze(.init(
                    output: .manualTyped(output.id), inputs: [.manualTyped(input.id)], timeZone: utc
                ), asOf: date(337))
                let estimate = try #require(result.estimates.first)
                if estimate.interval.contains(difference) { covered[scenario] += 1 }
                totalWidths[scenario] += estimate.interval.upperBound - estimate.interval.lowerBound
                totalErrors[scenario] += estimate.difference - difference
                #expect(result.evidence.dependenceLagDays == 14)
            }
        }
        #expect(Double(covered[0]) / Double(trials) >= 0.85)
        #expect(Double(covered[1]) / Double(trials) >= 0.85)
        #expect(totalWidths[1] > 1.15 * totalWidths[0])
        #expect(totalErrors.allSatisfy { abs($0 / Double(trials)) < 0.025 })
    }

    private func count(_ name: String, in app: HealthAnalysisApplication) throws -> TypedTrackingVariable {
        try app.manualLog.createTypedVariable(name: name, kind: .count, defaultValue: .count(0), startsOn: day(0))
    }

    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }

    private func date(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_704_067_200 + Double(offset) * 86_400)
    }

    private func day(_ offset: Int) -> ManualLogDay {
        ManualLogDay(date(offset), timeZone: utc)
    }

    private func binary(_ name: String, in app: HealthAnalysisApplication, starting offset: Int = 0) throws -> TypedTrackingVariable {
        try app.manualLog.createTypedVariable(
            name: name, kind: .yesNo, defaultValue: .yesNo(false), startsOn: day(offset)
        )
    }
}

private struct BinaryRandom {
    var state: UInt64

    mutating func uniform() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var bits = state
        bits = (bits ^ (bits >> 30)) &* 0xBF58476D1CE4E5B9
        bits = (bits ^ (bits >> 27)) &* 0x94D049BB133111EB
        return Double((bits ^ (bits >> 31)) >> 11) / 9_007_199_254_740_992
    }
}

private struct BinaryTestHealthSource: HealthMeasurementSource {
    let records: [HealthMeasurement]

    func requestReadAccess() async throws {}

    func readChanges(
        after anchors: [String: Data], includingPreviouslySaved: Bool
    ) async throws -> [HealthMeasurementChanges] {
        [.init(queryID: "restingHeartRate", anchor: Data([1]), added: records)]
    }
}
