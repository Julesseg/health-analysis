import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct CategoryAnalysisTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let today: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.startOfDay(for: .now)
    }()

    @Test func reopenedLogComparesNamedCategoriesAndExcludesOtherInputLevels() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appending(path: "log.json")
        let app = HealthAnalysisApplication(manualLogStoreURL: logURL)
        let office = TrackingCategory(name: "Office")
        let travel = TrackingCategory(name: "Travel")
        let home = TrackingCategory(name: "Home")
        let setting = try category("Work setting", options: [office, travel, home], defaultingTo: home, in: app)
        let output = try app.manualLog.createTypedVariable(
            name: "Headaches", kind: .count, defaultValue: .count(0), startsOn: day(1)
        )
        for index in 0..<120 {
            let level = [home, office, travel][index % 3]
            let count = [2, 4, 50][index % 3] + index / 3 % 4 - 1
            app.manualLog.editTypedEntry(setting.id, on: day(index), value: .category(level.id))
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .count(count))
        }
        let inputID = AnalysisSeriesID.manualTyped(setting.id)
        let configuration = AnalysisConfiguration(
            output: .manualTyped(output.id), inputs: [inputID], timeZone: utc,
            categories: .init(inputContrasts: [inputID: .init(reference: home.id, comparison: office.id)])
        )
        let reopened = HealthAnalysisApplication(manualLogStoreURL: logURL)
        let variable = try #require(reopened.analysisVariables.first { $0.id == inputID })
        #expect(variable.supportsInput && variable.supportsOutput)
        #expect(variable.kind == .tracked(.category([office, travel, home])))

        let result = try reopened.analyze(configuration, asOf: date(121))
        let estimate = try #require(result.estimates.first)
        #expect(estimate.scale == .proportionalCountChange)
        // Means are 2.5 at Home and 4.5 at the Office.
        #expect(abs(estimate.difference - 0.8) < 0.001)
        #expect(estimate.interval.contains(0.8))
        #expect(result.observations.count == 80)
        #expect(result.observations.prefix(2).compactMap { $0.inputs.first?.trackingValue } == [
            .category(home.id), .category(office.id)
        ])
        let evidence = try #require(result.categoryEvidence)
        #expect(evidence.excludedOutputDates.count == 40)
        #expect(evidence.excludedOutputDates.first == date(3))
        #expect(evidence.inputLevels[inputID]?.map(\.category.id) == [home.id, office.id])
        #expect(evidence.inputLevels[inputID]?.map(\.recordedDayCount) == [40, 40])
        let excluded = try #require(result.inspection?.unpairedOutputs.first { $0.date == date(3) })
        #expect(excluded.missingInputs.isEmpty)
        #expect(excluded.excludedCategoryInputs?.first?.category == travel.id)
        #expect(excluded.excludedCategoryInputs?.first?.origin == .observation)

        var reversed = configuration
        reversed.categories?.inputContrasts[inputID] = .init(reference: office.id, comparison: home.id)
        let reverseEstimate = try #require(reopened.analyze(reversed, asOf: date(121)).estimates.first)
        #expect(abs(reverseEstimate.difference - (2.5 / 4.5 - 1)) < 0.001)
    }

    @Test func selectedCategoryOutcomeRetainsAdjustedOddsAndEvidenceAcrossSavedRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appending(path: "log.json")
        let savedURL = directory.appending(path: "analyses.json")
        let app = HealthAnalysisApplication(manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL)
        let office = TrackingCategory(name: "Office")
        let home = TrackingCategory(name: "Home")
        let setting = try category("Work setting", options: [office, home], defaultingTo: home, in: app)
        let early = TrackingCategory(name: "Early")
        let late = TrackingCategory(name: "Late")
        let shift = try category("Shift", options: [late, early], defaultingTo: early, in: app)
        let migraine = TrackingCategory(name: "Migraine")
        let none = TrackingCategory(name: "None")
        let tension = TrackingCategory(name: "Tension")
        let outcome = try category(
            "Headache type", options: [tension, migraine, none], defaultingTo: none, starting: 1, in: app
        )
        for index in 0..<240 {
            let cell = index % 4
            let rep = index / 4
            let level = cell.isMultiple(of: 2) ? home : office
            let shiftLevel = cell < 2 ? early : late
            let event = rep * 17 % 60 < [12, 36, 20, 45][cell]
            let observed = event ? migraine : (rep.isMultiple(of: 2) ? tension : none)
            app.manualLog.editTypedEntry(setting.id, on: day(index), value: .category(level.id))
            app.manualLog.editTypedEntry(shift.id, on: day(index), value: .category(shiftLevel.id))
            if index == 4 {
                try app.manualLog.confirmDay(day(index + 1))
            } else {
                app.manualLog.editTypedEntry(outcome.id, on: day(index + 1), value: .category(observed.id))
            }
        }
        let settingID = AnalysisSeriesID.manualTyped(setting.id)
        let shiftID = AnalysisSeriesID.manualTyped(shift.id)
        let configuration = AnalysisConfiguration(
            output: .manualTyped(outcome.id), inputs: [settingID], adjustmentInputs: [shiftID], timeZone: utc,
            categories: .init(inputContrasts: [
                settingID: .init(reference: home.id, comparison: office.id),
                shiftID: .init(reference: early.id, comparison: late.id)
            ], outputEvent: migraine.id)
        )
        let completed = try #require(await app.refreshAnalysis(configuration)).get()
        let saved = try app.savedAnalyses.save(configuration, completed: completed)
        let reopened = HealthAnalysisApplication(manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL)
        let savedResult = try #require(reopened.savedAnalyses.state(for: saved.id).completed?.result)
        #expect(savedResult.configuration == configuration)
        #expect(savedResult.model == .categoryEventLogisticV1)
        #expect(savedResult.outputVariable?.categories == [tension, migraine, none])
        #expect(savedResult.modeledInputs.map(\.role) == [.input, .adjustment])
        #expect(savedResult.estimates.count == 2)
        for (estimate, oddsRatio) in zip(savedResult.estimates, [6.0, 2.0]) {
            #expect(estimate.scale == .proportionalCategoryOddsChange)
            #expect(abs(estimate.difference - (oddsRatio - 1)) < 0.001)
            #expect(estimate.interval.contains(oddsRatio - 1))
        }
        let levels = try #require(savedResult.categoryEvidence?.outputLevels)
        #expect(levels.map(\.category.id) == [tension.id, migraine.id, none.id])
        #expect(levels.first { $0.id == migraine.id }?.recordedDayCount == 113)
        #expect(savedResult.evidence.defaultDayCount == 1)
        #expect(savedResult.evidence.dependenceLagDays == 13)
        #expect(savedResult.evidence.grade == .low)
        #expect(savedResult.observations[4].outputTrackingValue == .category(none.id))
        #expect(savedResult.observations[4].outputOrigin == .assumedDefault(effectiveOn: day(1)))
        #expect(savedResult.healthHistoryReadAt == nil)
        await reopened.refreshSavedAnalysis(saved.id)
        let refreshed = try #require(reopened.savedAnalyses.state(for: saved.id).completed?.result)
        #expect(refreshed.configuration == configuration)
        #expect(refreshed.estimates.first?.difference == savedResult.estimates.first?.difference)
    }

    @Test func sparseClassesAndSeparatedOutcomesKeepTheirEvidenceWithoutAnEstimate() throws {
        let app = HealthAnalysisApplication()
        let office = TrackingCategory(name: "Office")
        let home = TrackingCategory(name: "Home")
        let setting = try category("Work setting", options: [office, home], defaultingTo: office, in: app)
        let present = TrackingCategory(name: "Migraine")
        let absent = TrackingCategory(name: "None")
        let output = try category("Headache type", options: [absent, present], defaultingTo: absent, starting: 1, in: app)
        let inputID = AnalysisSeriesID.manualTyped(setting.id)
        let configuration = AnalysisConfiguration(
            output: .manualTyped(output.id), inputs: [inputID], timeZone: utc,
            categories: .init(inputContrasts: [inputID: .init(reference: home.id, comparison: office.id)], outputEvent: present.id)
        )
        for index in 0..<84 {
            if index.isMultiple(of: 2) || index < 6 {
                let level = index.isMultiple(of: 2) ? home : office
                app.manualLog.editTypedEntry(setting.id, on: day(index), value: .category(level.id))
            }
            let value = index.isMultiple(of: 4) ? present : absent
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .category(value.id))
        }
        let sparseInput = try app.analyze(configuration, asOf: date(85))
        #expect(sparseInput.evidence.reasons == [.sparseCategoryInputs([inputID])])
        #expect(sparseInput.estimates.isEmpty)
        #expect(sparseInput.categoryEvidence?.inputLevels[inputID]?.last?.pairedDayCount == 42)
        #expect(sparseInput.categoryEvidence?.inputLevels[inputID]?.last?.recordedDayCount == 3)

        for index in 0..<84 {
            let level = index.isMultiple(of: 2) ? home : office
            app.manualLog.editTypedEntry(setting.id, on: day(index), value: .category(level.id))
            let value = index < 6 ? present : absent
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .category(value.id))
        }
        let sparseOutput = try app.analyze(configuration, asOf: date(85))
        #expect(sparseOutput.evidence.reasons == [.sparseCategoryOutput])
        #expect(sparseOutput.estimates.isEmpty)

        for index in 0..<84 {
            let value = index.isMultiple(of: 2) ? present : absent
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .category(value.id))
        }
        let separated = try app.analyze(configuration, asOf: date(85))
        #expect(separated.evidence.reasons == [.sparseCategoryEventByInput([inputID])])
        #expect(separated.estimates.isEmpty)
        #expect(separated.categoryEvidence?.inputLevels[inputID]?.first?.eventSupport?.otherDayCount == 0)

        let quantity = try app.manualLog.createQuantity(name: "Training", unit: "min", defaultValue: 0, startsOn: day(0))
        for index in 0..<84 {
            app.manualLog.editQuantity(
                quantity.id, on: day(index), text: index.isMultiple(of: 2) ? "10" : "0", locale: Locale(identifier: "en_US")
            )
        }
        var numeric = configuration
        numeric.inputs = [.manualQuantity(quantity.id)]
        numeric.categories?.inputContrasts = [:]
        let numericalSeparation = try app.analyze(numeric, asOf: date(85))
        #expect(numericalSeparation.evidence.reasons == [.categoryEventModelUnavailable])
        #expect(numericalSeparation.estimates.isEmpty)
    }

    @Test func categoryAnalysisRequiresExplicitCompatibleSelections() throws {
        let app = HealthAnalysisApplication()
        let home = TrackingCategory(name: "Home")
        let office = TrackingCategory(name: "Office")
        let setting = try category("Work setting", options: [home, office], defaultingTo: home, in: app)
        let migraine = TrackingCategory(name: "Migraine")
        let none = TrackingCategory(name: "None")
        let output = try category("Headache type", options: [migraine, none], defaultingTo: none, starting: 1, in: app)
        let quantity = try app.manualLog.createQuantity(name: "Training", unit: "min", defaultValue: 0, startsOn: day(0))
        let input = AnalysisSeriesID.manualTyped(setting.id)
        let other = AnalysisSeriesID.manualQuantity(quantity.id)
        var configuration = AnalysisConfiguration(output: .manualTyped(output.id), inputs: [input, other], timeZone: utc)
        #expect(throws: AnalysisRunFailure.categorySelectionUnavailable) { try app.analyze(configuration) }

        configuration.categories = .init(
            inputContrasts: [input: .init(reference: home.id, comparison: home.id)], outputEvent: migraine.id
        )
        #expect(throws: AnalysisRunFailure.categorySelectionUnavailable) { try app.analyze(configuration) }
        configuration.categories?.inputContrasts[input]?.comparison = office.id
        configuration.categories?.outputEvent = home.id
        #expect(throws: AnalysisRunFailure.categorySelectionUnavailable) { try app.analyze(configuration) }

        configuration.categories?.outputEvent = migraine.id
        configuration.behaviorWindow = .precedingWeek
        #expect(throws: AnalysisRunFailure.categoryWindowUnavailable) { try app.analyze(configuration) }
        configuration.behaviorWindow = .precedingDay
        configuration.interaction = .init(focal: input, moderator: other)
        #expect(throws: AnalysisRunFailure.categoryInteractionUnavailable) { try app.analyze(configuration) }
    }

    @Test func intervalsReflectSerialDependenceForNullAndKnownCategoryOdds() throws {
        let trials = 60
        let days = 336
        var covered = [0, 0]
        var width = [0.0, 0.0]
        var bias = [0.0, 0.0]
        let reference = TrackingCategory(name: "Home")
        let comparison = TrackingCategory(name: "Office")
        let event = TrackingCategory(name: "Migraine")
        let other = TrackingCategory(name: "None")
        for trial in 0..<trials {
            let comparisonProbability = trial.isMultiple(of: 2) ? 0.25 : 0.5
            let logOddsEffect = trial.isMultiple(of: 2) ? 0.0 : log(3.0)
            for (scenario, persistence) in [0.0, 0.8].enumerated() {
                let app = HealthAnalysisApplication()
                let input = try category("Work setting", options: [comparison, reference], defaultingTo: reference, in: app)
                let output = try category("Headache type", options: [other, event], defaultingTo: other, starting: 1, in: app)
                var groupRandom = CategoryRandom(state: UInt64(34_567 + trial))
                var eventRandom = CategoryRandom(state: UInt64(981_223 + trial))
                var compared = false
                var uniform = eventRandom.uniform()
                for index in 0..<days {
                    if index.isMultiple(of: 7) { compared = groupRandom.uniform() < 0.5 }
                    if eventRandom.uniform() >= persistence { uniform = eventRandom.uniform() }
                    let isEvent = uniform < (compared ? comparisonProbability : 0.25)
                    app.manualLog.editTypedEntry(input.id, on: day(index), value: .category(compared ? comparison.id : reference.id))
                    app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .category(isEvent ? event.id : other.id))
                }
                let inputID = AnalysisSeriesID.manualTyped(input.id)
                let result = try app.analyze(.init(
                    output: .manualTyped(output.id), inputs: [inputID], timeZone: utc,
                    categories: .init(
                        inputContrasts: [inputID: .init(reference: reference.id, comparison: comparison.id)], outputEvent: event.id
                    )
                ), asOf: date(days + 1))
                let estimate = try #require(result.estimates.first)
                if estimate.interval.contains(expm1(logOddsEffect)) { covered[scenario] += 1 }
                width[scenario] += log1p(estimate.interval.upperBound) - log1p(estimate.interval.lowerBound)
                bias[scenario] += log1p(estimate.difference) - logOddsEffect
                #expect(result.evidence.dependenceLagDays == 14)
            }
        }
        #expect(covered[0] >= 52)
        #expect(covered[1] >= 50)
        #expect(width[1] / width[0] > 1.2)
        #expect(abs(bias[0] / Double(trials)) < 0.12)
        #expect(abs(bias[1] / Double(trials)) < 0.12)
    }

    private func date(_ offset: Int) -> Date {
        today.addingTimeInterval(Double(offset - 241) * 86_400)
    }

    private func day(_ offset: Int) -> ManualLogDay {
        ManualLogDay(date(offset), timeZone: utc)
    }

    private func category(
        _ name: String, options: [TrackingCategory], defaultingTo initial: TrackingCategory,
        starting start: Int = 0, in app: HealthAnalysisApplication
    ) throws -> TypedTrackingVariable {
        try app.manualLog.createTypedVariable(
            name: name, kind: .category(options), defaultValue: .category(initial.id), startsOn: day(start)
        )
    }
}

private struct CategoryRandom {
    var state: UInt64

    mutating func uniform() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / 9_007_199_254_740_992
    }
}
