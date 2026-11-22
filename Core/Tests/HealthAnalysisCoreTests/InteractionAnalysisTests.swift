import Foundation
import HealthAnalysisCore
import Testing

extension AdjustedAnalysisTests {
    @Test func comparesAnInputAssociationAcrossObservedConditionsInOneJointFit() async throws {
        let (app, ids) = try await prepare(history: interactionHistory(strength: 3), units: ["mg", "L", "h", "g"], reopen: true)
        var question = configuration(inputs: Array(ids.prefix(3)), adjustments: [ids[3]])
        let pair = AnalysisInteraction(focal: question.inputs[0], moderator: question.inputs[1])
        question.interaction = pair

        let result = try app.analyze(question)
        let comparison = try #require(result.interaction)
        #expect(result.configuration.interaction == pair)
        #expect(result.model == .numericInteractionV1)
        #expect(result.estimates.map(\.input) == question.inputs + question.adjustmentInputs)
        #expect(result.evidence.grade == .low)
        #expect(result.evidence.dependenceLagDays == 11)
        #expect(comparison.focalValues == 100...200)
        #expect(comparison.lowerCondition.moderatorValue == 1)
        #expect(comparison.higherCondition.moderatorValue == 3)
        #expect(abs(comparison.lowerCondition.difference - 2) < 0.05)
        #expect(abs(comparison.higherCondition.difference - 8) < 0.05)
        #expect(abs(comparison.difference - 6) < 0.05)
        #expect(comparison.lowerCondition.interval.contains(2))
        #expect(comparison.higherCondition.interval.contains(8))
        #expect(comparison.interval.contains(6))
        let mainEffect = try #require(result.estimates.first)
        #expect(mainEffect.reference?.input == pair.moderator)
        #expect(mainEffect.reference?.value == 2)
        #expect(abs(mainEffect.difference - 5) < 0.05)
        #expect(abs(try #require(result.estimates.dropFirst(2).first).difference + 0.4) < 0.05)
    }

    @Test(arguments: [false, true])
    func withholdsComparisonsForPoorlyRepresentedCombinations(useDefaults: Bool) async throws {
        var history = interactionHistory(strength: 3)
        let underrepresented = history.indices.filter { history[$0].amounts.prefix(2).elementsEqual([100, 3]) }
        for (index, day) in underrepresented.dropFirst(3).enumerated() {
            if useDefaults {
                history[day].amounts[0] = nil
            } else if index.isMultiple(of: 2) {
                history[day].amounts[0] = 150
            } else {
                history[day].amounts[1] = 2
            }
        }
        let (app, ids) = try await prepare(
            history: history, units: ["mg", "L", "h", "g"], defaults: [100, 0, 0, 0]
        )
        var question = configuration(inputs: Array(ids.prefix(3)), adjustments: [ids[3]])
        question.interaction = .init(focal: question.inputs[0], moderator: question.inputs[1])
        let result = try app.analyze(question)
        #expect(result.coverage.usableDates.count == 144)
        #expect(result.evidence.grade == .insufficient)
        #expect(result.interaction == nil)
        #expect(result.estimates.isEmpty)
        let support = try #require(result.evidence.reasons.compactMap { reason -> AnalysisInteractionSupport? in
            if case .poorlyRepresentedInteraction(let support) = reason { return support }
            return nil
        }.first)
        #expect(support.explicitDaysByCombination[.lowerFocalHigherModerator] == 3)
        #expect(support.minimumDaysPerCombination == 5)
    }

    @Test func distinguishesAnEstimatedNearZeroInteractionFromAnUnavailableComparison() async throws {
        let (app, ids) = try await prepare(history: interactionHistory(strength: 0), units: ["mg", "L", "h", "g"])
        var question = configuration(inputs: Array(ids.prefix(3)), adjustments: [ids[3]])
        question.interaction = .init(focal: question.inputs[0], moderator: question.inputs[1])

        let result = try app.analyze(question)
        let comparison = try #require(result.interaction)
        #expect(comparison.finding == .nearZero)
        #expect(comparison.interval.contains(0))
        #expect(comparison.interval.lowerBound >= -1 && comparison.interval.upperBound <= 1)
        #expect(comparison.lowerCondition.interval.contains(5))
        #expect(comparison.higherCondition.interval.contains(5))
        #expect(result.evidence.grade == .low)
    }

    @Test(arguments: [0.0, 0.001])
    func reportsCollinearityThatOnlyAppearsWhenTheInteractionIsIncluded(perturbation: Double) async throws {
        let history = interactionHistory(strength: 3).enumerated().map { index, day in
            var day = day
            let caffeine = (day.amounts[0]! - 150) / 50
            let fluids = day.amounts[1]! - 2
            let noise = index / 18 % 2 == 0 ? -perturbation : perturbation
            day.amounts[3] = 2 + caffeine / 3 + caffeine * fluids + noise
            return day
        }
        let (app, ids) = try await prepare(history: history, units: ["mg", "L", "h", "g"])
        var question = configuration(inputs: Array(ids.prefix(3)), adjustments: [ids[3]])
        #expect(try app.analyze(question).estimates.count == 4)
        question.interaction = .init(focal: question.inputs[0], moderator: question.inputs[1])

        let result = try app.analyze(question)
        #expect(result.evidence.grade == .insufficient)
        #expect(result.interaction == nil)
        #expect(result.estimates.isEmpty)
        #expect(result.evidence.reasons == [
            .collinearInputs([question.inputs[0], question.inputs[1], question.adjustmentInputs[0]])
        ])
    }

    @Test func rejectsAnInteractionThatDoesNotReferenceTwoDistinctSelectedInputs() async throws {
        let (app, ids) = try await prepare(history: [], units: ["mg", "L", "h"])
        var question = configuration(inputs: Array(ids.prefix(2)), adjustments: [ids[2]])
        for moderator in [question.inputs[0], question.adjustmentInputs[0], .manualQuantity(UUID())] {
            question.interaction = .init(focal: question.inputs[0], moderator: moderator)
            #expect(throws: AnalysisRunFailure.unsupportedConfiguration) { try app.analyze(question) }
        }
    }

    @Test func reloadsACachedInteractionAndInvalidatesItWhenThePairChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let savedURL = directory.appending(path: "saved.json")
        let (app, ids) = try await prepare(
            history: interactionHistory(strength: 3), units: ["mg", "L", "h", "g"], savedURL: savedURL
        )
        var question = configuration(inputs: Array(ids.prefix(3)), adjustments: [ids[3]])
        question.interaction = .init(focal: question.inputs[0], moderator: question.inputs[1])
        let saved = try app.savedAnalyses.save(question)
        try app.savedAnalyses.setPinned(true, for: saved.id)

        await app.refreshSavedAnalysis(saved.id)

        let reopened = HealthAnalysisApplication(savedAnalysesStoreURL: savedURL)
        let cached = try #require(reopened.savedAnalyses.state(for: saved.id).completed?.result)
        #expect(reopened.savedAnalyses.following.first?.configuration == question)
        #expect(cached.configuration == question)
        #expect(cached.interaction?.interval.contains(6) == true)
        #expect(cached.interaction?.support.explicitlyObservedPairDays == 144)

        question.interaction = .init(focal: question.inputs[0], moderator: question.inputs[2])
        try reopened.savedAnalyses.save(question, updating: saved.id)
        let edited = HealthAnalysisApplication(savedAnalysesStoreURL: savedURL)
        #expect(edited.savedAnalyses.following.first?.configuration == question)
        #expect(edited.savedAnalyses.state(for: saved.id).completed == nil)
    }

    @Test func interactionIntervalsAccountForDependentScoresAcrossCalendarGaps() async throws {
        let numberOfTrials = 64
        var averageWidths: [Double] = []
        for persistence in [0.0, 0.8] {
            var available = 0
            var covered = 0
            var totalWidth = 0.0
            for trial in 0..<numberOfTrials {
                let strength = trial.isMultiple(of: 2) ? 0.0 : 1.2
                let result = try await simulateInteraction(
                    strength: strength, seed: UInt64(12_000 + trial), persistence: persistence
                )
                #expect(result.coverage.missingDays == 54)
                guard let comparison = result.interaction else {
                    #expect(result.evidence.reasons.contains {
                        if case .poorlyRepresentedInteraction = $0 { return true }
                        return false
                    })
                    continue
                }
                let focalChange = comparison.focalValues.upperBound - comparison.focalValues.lowerBound
                let moderatorChange = comparison.higherCondition.moderatorValue - comparison.lowerCondition.moderatorValue
                let trueChange = strength * focalChange * moderatorChange
                available += 1
                if comparison.interval.contains(trueChange) { covered += 1 }
                totalWidth += comparison.interval.upperBound - comparison.interval.lowerBound
            }
            try #require(available >= 56)
            #expect((0.85...0.99).contains(Double(covered) / Double(available)))
            averageWidths.append(totalWidth / Double(available))
        }
        #expect(averageWidths[1] / averageWidths[0] > 1.25)
    }

    @Test func comparesKnownInteractionsAcrossCompleteOverlappingWeeks() async throws {
        let strength = 0.08
        let result = try await simulateInteraction(
            strength: strength, seed: 10_234, persistence: 0.3, window: .precedingWeek
        )
        let comparison = try #require(result.interaction)
        let firstWindow = try #require(result.observations.first?.inputs.first)
        #expect(firstWindow.days.count == 7)
        #expect(result.coverage.nonOverlappingWindowCount < result.observations.count)
        #expect(result.evidence.grade == .low)
        #expect(result.evidence.reasons.contains(.overlappingBehaviorWindows))
        let focalChange = comparison.focalValues.upperBound - comparison.focalValues.lowerBound
        let moderatorChange = comparison.higherCondition.moderatorValue - comparison.lowerCondition.moderatorValue
        let knownDifference = strength * focalChange * moderatorChange
        #expect(abs(comparison.difference - knownDifference) < 0.3)
        #expect(comparison.interval.contains(knownDifference))
    }

    private func simulateInteraction(
        strength: Double, seed: UInt64, persistence: Double, window: AnalysisBehaviorWindow = .precedingDay
    ) async throws -> AnalysisResult {
        var random = AdjustedGaussianSequence(seed: seed)
        var state = (0..<4).map { _ in random.next() }
        var dailyStates: [[Double]] = []
        let scale = sqrt(1 - persistence * persistence)
        let history = (0..<308).map { index in
            for term in state.indices {
                state[term] = persistence * state[term] + scale * random.next()
            }
            dailyStates.append(state)
            let days = dailyStates.suffix(window.dayCount)
            let focal = days.reduce(0) { $0 + $1[0] }
            let moderator = days.reduce(0) { $0 + $1[1] }
            let adjustment = days.reduce(0) { $0 + $1[2] }
            let bpm = 65 + 1.5 * focal - 0.7 * moderator + 0.8 * adjustment + strength * focal * moderator + 1.5 * state[3]
            return Day(amounts: [state[0] + 6, state[1] + 6, state[2] + 6], bpm: index % 17 >= 14 ? nil : bpm)
        }
        let (app, ids) = try await prepare(history: history, units: ["g", "L", "h"])
        var question = configuration(inputs: ids)
        question.behaviorWindow = window
        question.interaction = .init(focal: question.inputs[0], moderator: question.inputs[1])
        return try app.analyze(question)
    }

    private func interactionHistory(strength: Double) -> [Day] {
        (0..<144).map { index in
            let caffeine = 100.0 + Double(index % 3) * 50
            let fluids = 1.0 + Double(index / 3 % 3)
            let exercise = 7.0 + Double(index / 9 % 2) * 2
            let adjustment = 1.0 + Double(index / 18 % 2) * 2
            let noise = index / 36 % 2 == 0 ? -0.2 : 0.2
            let caffeineChange = (caffeine - 150) / 100
            let bpm = 65 + 5 * caffeineChange + 0.7 * (fluids - 2) - 0.4 * (exercise - 8)
                + 0.9 * (adjustment - 2) + strength * caffeineChange * (fluids - 2) + noise
            return Day(amounts: [caffeine, fluids, exercise, adjustment], bpm: bpm)
        }
    }
}
