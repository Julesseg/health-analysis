import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct RatingAnalysisTests {
    @Test func reopenedOrderedRatingsEstimateAnAdjustedThresholdContrastAndRefreshWithoutHealth() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appending(path: "log.json")
        let savedURL = directory.appending(path: "analyses.json")
        let app = HealthAnalysisApplication(manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL)
        let stress = try app.manualLog.createTypedVariable(
            name: "Stress", kind: .rating(1...5), defaultValue: .rating(1), startsOn: day(0)
        )
        let energy = try app.manualLog.createTypedVariable(
            name: "Energy", kind: .rating(2...8), defaultValue: .rating(8), startsOn: day(1)
        )
        let shifts = try app.manualLog.createTypedVariable(
            name: "Late shifts", kind: .count, defaultValue: .count(0), startsOn: day(0)
        )
        let pairedDays = 240
        var random = RatingRandom(state: 54_145)
        let assignments = [0] + Array(1..<pairedDays).shuffled(using: &random)
        for (index, assignment) in assignments.enumerated() {
            let highStress = assignment % 2
            let shift = assignment / 2 % 2
            let cycle = assignment / 4 % 10
            let stressLevel = highStress == 0 ? 1 + cycle % 2 : 3 + cycle % 3
            let energyLevel = cycle < 2 + 3 * highStress + 2 * shift ? 8 - cycle % 4 : 2 + cycle % 3
            if index != 0 {
                app.manualLog.editTypedEntry(stress.id, on: day(index), value: .rating(stressLevel))
            }
            app.manualLog.editTypedEntry(shifts.id, on: day(index), value: .count(shift))
            if index != 0 {
                app.manualLog.editTypedEntry(energy.id, on: day(index + 1), value: .rating(energyLevel))
            }
        }
        try app.manualLog.confirmDay(day(1))
        let reopened = HealthAnalysisApplication(manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL)
        let input = AnalysisSeriesID.manualTyped(stress.id)
        let output = AnalysisSeriesID.manualTyped(energy.id)
        let adjustment = AnalysisSeriesID.manualTyped(shifts.id)
        for id in [input, output] {
            let choice = try #require(reopened.analysisVariables.first { $0.id == id })
            #expect(choice.supportsInput && choice.supportsOutput)
        }
        let configuration = AnalysisConfiguration(
            output: output, inputs: [input], adjustmentInputs: [adjustment], timeZone: utc
        )
        let result = try reopened.analyze(configuration, asOf: date(pairedDays + 1))
        #expect(result.coverage.usableDates == (1...pairedDays).map(date))
        #expect(result.model == .ratingThresholdLinearV1)
        #expect(result.evidence.grade == .low)
        #expect(result.evidence.defaultDayCount == 1)
        #expect((result.evidence.dependenceLagDays ?? 0) >= 13)
        #expect(result.outputVariable?.kind == .tracked(.rating(2...8)))
        #expect(result.modeledInputs.map(\.role) == [.input, .adjustment])
        #expect(result.modeledInputs[0].kind == .tracked(.rating(1...5)))
        #expect(result.observations[0].outputTrackingValue == .rating(8))
        #expect(result.observations[0].outputOrigin == .assumedDefault(effectiveOn: day(1)))
        #expect(result.observations[0].inputs[0].trackingValue == .rating(1))
        #expect(result.observations[0].inputs[0].origin == .assumedDefault(effectiveOn: day(0)))
        #expect(result.outputEvidence.first?.trackingValue == .rating(8))
        #expect(result.outputEvidence.first?.isObserved == false)
        #expect(result.inputEvidence(for: input).pairs.first?.input.trackingValue == .rating(1))
        #expect(Set(result.observations.map(\.outputValue)) == Set((2...8).map(Double.init)))
        #expect(result.estimates.count == 2)
        for (estimate, expected) in zip(result.estimates, [0.3, 0.2]) {
            #expect(abs(estimate.difference - expected) < 1e-10)
            #expect(estimate.interval.contains(expected))
            #expect(estimate.finding == .higher)
            #expect(estimate.scale == .ratingThresholdProbabilityDifference)
        }
        #expect(result.healthHistoryReadAt == nil)

        let completed = try #require(await reopened.refreshAnalysis(configuration)).get()
        let saved = try reopened.savedAnalyses.save(configuration, completed: completed)
        let again = HealthAnalysisApplication(manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL)
        #expect(again.savedAnalyses.state(for: saved.id).completed?.result.outputVariable?.kind == .tracked(.rating(2...8)))
        await again.refreshSavedAnalysis(saved.id)
        let refreshed = try #require(again.savedAnalyses.state(for: saved.id).completed?.result)
        #expect(again.savedAnalyses.state(for: saved.id).failure == nil)
        #expect(refreshed.configuration == configuration)
        #expect(refreshed.observations.first?.outputOrigin == .assumedDefault(effectiveOn: day(1)))
        #expect(refreshed.estimates.count == 2)
    }

    @Test func recordedLevelsMustCrossTheThresholdAndDefaultsCannotSupplyTheMissingGroup() throws {
        let app = HealthAnalysisApplication()
        let stress = try app.manualLog.createTypedVariable(
            name: "Stress", kind: .rating(-4...1), defaultValue: .rating(0), startsOn: day(0)
        )
        let energy = try app.manualLog.createTypedVariable(
            name: "Energy", kind: .rating(1...5), defaultValue: .rating(3), startsOn: day(1)
        )
        let input = AnalysisSeriesID.manualTyped(stress.id)
        let output = AnalysisSeriesID.manualTyped(energy.id)
        let configuration = AnalysisConfiguration(output: output, inputs: [input], timeZone: utc)
        #expect(app.analysisVariables.first { $0.id == input }?.kind.ratingThreshold == -1)
        for index in 0..<60 {
            if index % 3 != 0 {
                app.manualLog.editTypedEntry(stress.id, on: day(index), value: .rating(-4 + index % 3))
            }
        }
        let defaultOutput = try app.analyze(configuration, asOf: date(61))
        #expect(defaultOutput.evidence.reasons == [.defaultOnlyOutput])
        #expect(defaultOutput.estimates.isEmpty)

        for index in 0..<60 where index % 3 != 0 {
            app.manualLog.editTypedEntry(energy.id, on: day(index + 1), value: .rating(1 + index % 2))
        }
        let sparseOutput = try app.analyze(configuration, asOf: date(61))
        #expect(sparseOutput.evidence.reasons == [.sparseObservedRatingOutput])
        #expect(sparseOutput.estimates.isEmpty)

        for index in 0..<60 where index % 3 == 0 {
            app.manualLog.editTypedEntry(energy.id, on: day(index + 1), value: .rating(5))
        }
        let sparseInput = try app.analyze(configuration, asOf: date(61))
        #expect(sparseInput.evidence.reasons == [.sparseObservedRatingInputs([input])])
        #expect(sparseInput.estimates.isEmpty)
        #expect(sparseInput.evidence.defaultDayCount == 20)
    }

    @Test func ratingAdjustmentKeepsTheCountModelAndRejectsUnsupportedWindowsAndInteractions() throws {
        let app = HealthAnalysisApplication()
        let stress = try app.manualLog.createTypedVariable(
            name: "Stress", kind: .rating(1...5), defaultValue: .rating(3), startsOn: day(0)
        )
        let exercise = try app.manualLog.createQuantity(name: "Exercise", unit: "min", defaultValue: 0, startsOn: day(0))
        let output = try app.manualLog.createTypedVariable(
            name: "Headaches", kind: .count, defaultValue: .count(0), startsOn: day(1)
        )
        for index in 0..<120 {
            let highStress = index % 2
            let exerciseMinutes = index / 2 % 2
            let cycle = index / 4
            let level = highStress == 0 ? 1 + cycle % 2 : 3 + cycle % 3
            app.manualLog.editTypedEntry(stress.id, on: day(index), value: .rating(level))
            app.manualLog.editQuantity(exercise.id, on: day(index), text: String(exerciseMinutes), locale: Locale(identifier: "en_US"))
            let count = (1 + highStress) * (1 + 2 * exerciseMinutes) + cycle % 3 - 1
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .count(count))
        }
        let stressID = AnalysisSeriesID.manualTyped(stress.id)
        let exerciseID = AnalysisSeriesID.manualQuantity(exercise.id)
        var configuration = AnalysisConfiguration(
            output: .manualTyped(output.id), inputs: [exerciseID], adjustmentInputs: [stressID], timeZone: utc
        )
        let result = try app.analyze(configuration, asOf: date(121))
        let adjusted = try #require(result.estimates.first { $0.input == stressID })
        #expect(result.model == .countLogLinearV1)
        #expect(adjusted.scale == .proportionalCountChange)
        #expect(abs(adjusted.difference - 1) < 0.01)
        #expect(adjusted.interval.contains(1))

        configuration.behaviorWindow = .precedingWeek
        #expect(throws: AnalysisRunFailure.ratingWindowUnavailable) {
            try app.analyze(configuration, asOf: date(121))
        }
        let other = try app.manualLog.createQuantity(name: "Caffeine", unit: "mg", defaultValue: 0, startsOn: day(0))
        let otherID = AnalysisSeriesID.manualQuantity(other.id)
        configuration.output = .health(metric: .restingHeartRate)
        configuration.behaviorWindow = .precedingDay
        configuration.inputs.append(otherID)
        configuration.interaction = .init(focal: exerciseID, moderator: otherID)
        #expect(throws: AnalysisRunFailure.ratingInteractionUnavailable) {
            try app.analyze(configuration, asOf: date(121))
        }
    }

    @Test func thresholdIntervalsCoverKnownContrastsWithSerialDependence() throws {
        let trials = 72
        let days = 336
        var coverage = [0, 0]
        var width = [0.0, 0.0]
        var bias = [0.0, 0.0]
        for trial in 0..<trials {
            let expected = trial.isMultiple(of: 2) ? 0.0 : 0.2
            for (scenario, persistence) in [0.0, 0.8].enumerated() {
                let app = HealthAnalysisApplication()
                let stress = try app.manualLog.createTypedVariable(
                    name: "Stress", kind: .rating(1...5), defaultValue: .rating(1), startsOn: day(0)
                )
                let energy = try app.manualLog.createTypedVariable(
                    name: "Energy", kind: .rating(2...8), defaultValue: .rating(2), startsOn: day(1)
                )
                var random = RatingRandom(state: UInt64(trial + 47_000))
                var outcomeRandom = RatingRandom(state: UInt64(trial + 932_000))
                var stressGroup = 0
                var latent = outcomeRandom.uniform()
                for index in 0..<days {
                    if index.isMultiple(of: 14) { stressGroup = random.uniform() < 0.5 ? 0 : 1 }
                    let renew = outcomeRandom.uniform() >= persistence
                    let draw = outcomeRandom.uniform()
                    if renew { latent = draw }
                    let thresholdProbability = 0.35 + expected * Double(stressGroup)
                    let stressLevel = stressGroup == 0 ? 1 + index % 2 : 3 + index % 3
                    let energyLevel = latent < thresholdProbability ? 5 + index % 4 : 2 + index % 3
                    app.manualLog.editTypedEntry(stress.id, on: day(index), value: .rating(stressLevel))
                    app.manualLog.editTypedEntry(energy.id, on: day(index + 1), value: .rating(energyLevel))
                }
                let result = try app.analyze(.init(
                    output: .manualTyped(energy.id), inputs: [.manualTyped(stress.id)], timeZone: utc
                ), asOf: date(days + 1))
                let estimate = try #require(result.estimates.first)
                if estimate.interval.contains(expected) { coverage[scenario] += 1 }
                width[scenario] += estimate.interval.upperBound - estimate.interval.lowerBound
                bias[scenario] += estimate.difference - expected
                #expect(result.evidence.grade == .low)
            }
        }
        #expect((0.85...1).contains(Double(coverage[0]) / Double(trials)))
        #expect((0.91...1).contains(Double(coverage[1]) / Double(trials)))
        #expect(width[1] / width[0] > 1.3)
        #expect(abs(bias[0] / Double(trials)) < 0.035)
        #expect(abs(bias[1] / Double(trials)) < 0.035)
    }

    private let utc = TimeZone(secondsFromGMT: 0)!

    private func date(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_735_689_600 + Double(offset) * 86_400)
    }

    private func day(_ offset: Int) -> ManualLogDay {
        ManualLogDay(date(offset), timeZone: utc)
    }
}

private struct RatingRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
        return mixed ^ (mixed >> 31)
    }

    mutating func uniform() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992
    }
}
