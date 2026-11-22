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
        for index in 0..<120 {
            let highStress = index % 2
            let shift = index / 2 % 2
            let cycle = index / 4 % 10
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
        let result = try reopened.analyze(configuration, asOf: date(121))
        #expect(result.coverage.usableDates == (1...120).map(date))
        #expect(result.model == .ratingThresholdLinearV1)
        #expect(result.evidence.grade == .low)
        #expect(result.evidence.defaultDayCount == 1)
        #expect(result.evidence.dependenceLagDays == 10)
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

    private let utc = TimeZone(secondsFromGMT: 0)!

    private func date(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_735_689_600 + Double(offset) * 86_400)
    }

    private func day(_ offset: Int) -> ManualLogDay {
        ManualLogDay(date(offset), timeZone: utc)
    }
}
