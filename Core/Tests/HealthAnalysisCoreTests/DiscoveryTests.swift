import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct DiscoveryTests {
    @Test func searchesAnEnabledQuantityAcrossEveryWindowAndRetainsTheSelectionBoundary() async throws {
        let fixture = DiscoveryHistory()
        let (application, inputs) = try await fixture.application(
            days: 395, inputNames: ["Caffeine", "Disabled"],
            values: { day in [100 + day * 71 % 251, day * 29 % 131] },
            output: { day, values in 60 + 0.04 * Double(values[day - 1][0]) + Double(day * 13 % 17) / 20 }
        )
        let report = try #require(await application.discover(
            asOf: fixture.cutoff, timeZone: fixture.timeZone, enabledSeries: [inputs[0], fixture.output]
        ))
        #expect(report.candidates.map(\.configuration.behaviorWindow) == AnalysisBehaviorWindow.allCases)
        #expect(report.candidates.allSatisfy { $0.configuration.inputs == [inputs[0]] })
        #expect(report.candidates.allSatisfy { $0.configuration.output == fixture.output })
        let finding = try #require(report.findings.first { $0.configuration.behaviorWindow == .precedingDay })
        #expect(finding.completed.updatedAt == fixture.cutoff)
        #expect(finding.completed.discovery?.cutoff == fixture.cutoff)
        #expect(finding.completed.result.outputSource == fixture.source)
        #expect(finding.completed.result.coverage.usableDates.count == 365)
        #expect(finding.completed.result.observations.allSatisfy { $0.outputAnchor < fixture.cutoff })
        #expect(finding.completed.result.estimates.first.map { abs($0.difference - 4) < 0.1 } == true)
        #expect(finding.completed.discovery?.familySize == 3)
        #expect(finding.completed.result.evidence.grade == .low)
    }
    @Test func savingAndRefreshingPreservesTheOriginalSelectionForTheSameQuestion() async throws {
        let store = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: store) }
        let url = store.appending(path: "questions.json")
        let fixture = DiscoveryHistory()
        let (application, _) = try await fixture.application(
            days: 395, inputNames: ["Caffeine"], storeURL: url,
            values: { [100 + $0 * 71 % 251] },
            output: { day, values in 60 + 0.04 * Double(values[day - 1][0]) + Double(day * 13 % 17) / 20 }
        )
        let report = try #require(await application.discover(asOf: fixture.cutoff, timeZone: fixture.timeZone))
        let finding = try #require(report.findings.first { $0.configuration.behaviorWindow == .precedingDay })
        let question = try application.savedAnalyses.save(finding.configuration, completed: finding.completed)
        try application.savedAnalyses.setPinned(true, for: question.id)

        let reopened = HealthAnalysisApplication(savedAnalysesStoreURL: url).savedAnalyses
        #expect(reopened.following.first?.configuration == finding.configuration)
        #expect(reopened.state(for: question.id).completed?.updatedAt == fixture.cutoff)
        #expect(reopened.state(for: question.id).completed?.discovery?.contrast == finding.completed.discovery?.contrast)
        #expect(reopened.discoveryBaseline(for: question.id)?.result.outputSource == fixture.source)

        await application.refreshSavedAnalysis(question.id)
        let refreshed = HealthAnalysisApplication(savedAnalysesStoreURL: url).savedAnalyses
        #expect(refreshed.state(for: question.id).completed?.result.configuration == finding.configuration)
        #expect(refreshed.state(for: question.id).completed?.discovery == nil)
        let baseline = try #require(refreshed.discoveryBaseline(for: question.id))
        #expect(baseline.discovery?.cutoff == fixture.cutoff)
        #expect(baseline.result.estimates.first?.difference == finding.completed.result.estimates.first?.difference)
        #expect(baseline.result.configuration == finding.configuration)

        var edited = finding.configuration
        edited.behaviorWindow = .precedingWeek
        try refreshed.save(edited, updating: question.id, completed: finding.completed)
        #expect(refreshed.following.first?.id == question.id)
        #expect(refreshed.discoveryBaseline(for: question.id) == nil)
        #expect(refreshed.state(for: question.id).completed == nil)
    }

    @Test(arguments: [0.0, 0.86])
    func nullSearchWithCalendarGapsAndDependentCandidates(dependence: Double) async throws {
        let fixture = DiscoveryHistory()
        var familiesWithARejection = 0
        var testedWindows: [AnalysisBehaviorWindow: Int] = [:]
        let trials = 64
        for trial in 0..<trials {
            var noise = DiscoveryNoise(seed: UInt64(trial + 901))
            let first = noise.series(count: 395, dependence: dependence)
            let second = noise.series(count: 395, dependence: dependence)
            let error = noise.series(count: 396, dependence: dependence)
            let (application, inputs) = try await fixture.application(
                days: 395, inputNames: ["Caffeine", "Other"], excluding: { $0 % 17 < 2 },
                values: { day in [first[day], second[day]].map { Int((220 + 35 * $0).rounded()) } },
                output: { day, _ in 70 + 2 * error[day] }
            )
            let report = try #require(await application.discover(asOf: fixture.cutoff, timeZone: fixture.timeZone))
            #expect(report.candidates.count == 15)
            if report.candidates.contains(where: { $0.adjustedPValue.map { $0 <= 0.05 } ?? false }) {
                familiesWithARejection += 1
            }
            for candidate in report.candidates where candidate.configuration.inputs == [inputs[0]]
                && candidate.configuration.adjustmentInputs.isEmpty && candidate.adjustedPValue != nil {
                testedWindows[candidate.configuration.behaviorWindow, default: 0] += 1
            }
        }
        print("Discovery null AR(1)=\(dependence) rejects \(familiesWithARejection)/\(trials) families; focal windows \(testedWindows)")
        #expect(familiesWithARejection <= 8)
        for window in AnalysisBehaviorWindow.allCases {
            #expect(testedWindows[window, default: 0] >= 56)
        }
    }

    @Test(arguments: [AnalysisBehaviorWindow.precedingWeek, .precedingMonth])
    func findsAPlantedAssociationOnCompleteOverlappingWindows(window: AnalysisBehaviorWindow) async throws {
        let fixture = DiscoveryHistory()
        var noise = DiscoveryNoise(seed: 765)
        let behavior = noise.series(count: 395, dependence: 0.65)
        let error = noise.series(count: 396, dependence: 0.80)
        let (application, _) = try await fixture.application(
            days: 395, inputNames: ["Caffeine"], excluding: { $0 % 17 < 2 },
            values: { [Int((220 + 35 * behavior[$0]).rounded())] },
            output: { day, values in
                let total = values[max(0, day - window.dayCount)..<day].reduce(0) { $0 + $1[0] - 220 }
                return 95 + 0.018 * Double(total) + error[day]
            }
        )
        let report = try #require(await application.discover(asOf: fixture.cutoff, timeZone: fixture.timeZone))
        let finding = try #require(report.findings.first { $0.configuration.behaviorWindow == window })
        let result = finding.completed.result
        let estimate = try #require(result.estimates.first)
        #expect(abs(estimate.difference - 1.8) < 0.20)
        #expect(result.coverage.nonOverlappingWindowCount < result.coverage.usableDates.count / 2)
        #expect(result.evidence.reasons.contains(.overlappingBehaviorWindows))
        #expect(result.observations.first?.inputs.first?.days.count == window.dayCount)
    }

    @Test func theAdjustmentSeparatesConfoundingAndWithholdsCollinearQuestions() async throws {
        let fixture = DiscoveryHistory()
        var noise = DiscoveryNoise(seed: 25_840)
        let cause = noise.series(count: 395, dependence: 0)
        let mixed = noise.series(count: 395, dependence: 0)
        let error = noise.series(count: 396, dependence: 0.5)
        let (application, inputs) = try await fixture.application(
            days: 395, inputNames: ["Caffeine", "Other", "Caffeine duplicate"],
            values: { day in
                let focal = Int((220 + 30 * cause[day] + 30 * mixed[day]).rounded())
                return [focal, Int((200 + 45 * cause[day]).rounded()), 2 * focal]
            },
            output: { day, values in 80 + 0.07 * Double(values[day - 1][1] - 200) + 0.6 * error[day] }
        )
        let report = try #require(await application.discover(asOf: fixture.cutoff, timeZone: fixture.timeZone))
        let day = report.candidates.filter { $0.configuration.behaviorWindow == .precedingDay }
        let marginal = try #require(day.first { $0.configuration.inputs == [inputs[0]]
            && $0.configuration.adjustmentInputs.isEmpty })
        let adjusted = try #require(day.first { $0.configuration.inputs == [inputs[0]]
            && $0.configuration.adjustmentInputs == [inputs[1]] })
        let other = try #require(day.first { $0.configuration.inputs == [inputs[1]]
            && $0.configuration.adjustmentInputs == [inputs[0]] })
        let collinear = try #require(day.first { $0.configuration.inputs == [inputs[0]]
            && $0.configuration.adjustmentInputs == [inputs[2]] })
        #expect(report.candidates.count == 36)
        #expect(try #require(marginal.adjustedPValue) <= 0.05)
        #expect(try #require(adjusted.adjustedPValue) > 0.05)
        #expect(try #require(other.adjustedPValue) <= 0.05)
        if case .modelInsufficient(let reasons) = collinear.outcome {
            #expect(reasons.contains(.collinearInputs([inputs[0], inputs[2]])))
        } else {
            Issue.record("A collinear adjustment was given a test result.")
        }
    }

    @Test func discoversAPlantedInteractionUsingOnlyTheConditionDifferenceForSelection() async throws {
        let fixture = DiscoveryHistory()
        var noise = DiscoveryNoise(seed: 517_796)
        let first = noise.series(count: 395, dependence: 0)
        let second = noise.series(count: 395, dependence: 0)
        let error = noise.series(count: 396, dependence: 0.55)
        let (application, inputs) = try await fixture.application(
            days: 395, inputNames: ["Caffeine", "Training"],
            values: { day in [first[day], second[day]].map { Int((200 + 30 * $0).rounded()) } },
            output: { day, values in
                let pair = values[day - 1]
                return 100 + 0.003 * Double((pair[0] - 200) * (pair[1] - 200)) + error[day] / 3
            }
        )
        let report = try #require(await application.discover(asOf: fixture.cutoff, timeZone: fixture.timeZone))
        let interaction = AnalysisInteraction(focal: inputs[0], moderator: inputs[1])
        let finding = try #require(report.findings.first {
            $0.configuration.behaviorWindow == .precedingDay && $0.configuration.interaction == interaction
        })
        let comparison = try #require(finding.completed.result.interaction)
        let focalRange = comparison.focalValues.upperBound - comparison.focalValues.lowerBound
        let moderatorRange = comparison.higherCondition.moderatorValue - comparison.lowerCondition.moderatorValue
        #expect(abs(comparison.difference - 0.003 * focalRange * moderatorRange) < 0.25)
        #expect(finding.completed.discovery?.contrast == .interaction(interaction))
        #expect(report.candidates.filter { $0.contrast == .interaction(interaction) }.count == 3)
    }

    @Test func publishesOnlyTheActiveScopeAndExplainsUnavailableEvidence() async throws {
        let fixture = DiscoveryHistory()
        let (application, inputs) = try await fixture.application(
            days: 395, inputNames: ["Caffeine"],
            values: { [100 + $0 * 71 % 251] },
            output: { day, values in 60 + 0.04 * Double(values[day - 1][0]) + Double(day * 13 % 17) / 20 }
        )
        await application.refreshDiscoveries(asOf: fixture.cutoff, timeZone: fixture.timeZone)
        #expect(application.overview.hasDiscoveries)
        #expect(application.discovery.report?.status == .findings)
        #expect(!application.discovery.isSearching)

        await application.refreshDiscoveries(
            asOf: fixture.cutoff, timeZone: fixture.timeZone, enabledSeries: [fixture.output]
        )
        #expect(!application.overview.hasDiscoveries)
        #expect(application.discovery.report?.status == .noEnabledInputs)

        await application.refreshDiscoveries(asOf: fixture.cutoff, timeZone: fixture.timeZone, enabledSeries: [inputs[0]])
        #expect(application.discovery.report?.status == .noEnabledOutputs)

        let empty = try #require(await HealthAnalysisApplication().discover(asOf: fixture.cutoff))
        #expect(empty.status == .noEnabledInputs)
    }

    @Test func familyIsBoundedAndIndependentOfOutputStrength() async throws {
        let fixture = DiscoveryHistory()
        let sleep = HealthMeasurement.Source(name: "Synthetic sleep", bundleIdentifier: "fixture.sleep")
        let sleepRecords = (1...395).map { day in
            HealthMeasurement(
                id: UUID(), metric: .sleepAnalysis, value: 3, unit: .sleepStage,
                startDate: fixture.date(day), endDate: fixture.date(day).addingTimeInterval(7 * 3600),
                source: sleep, timeZoneIdentifier: fixture.timeZone.identifier
            )
        }
        let (application, inputs) = try await fixture.application(
            days: 395, inputNames: ["Caffeine", "Second", "Third", "Fourth", "Beyond limit"],
            additionalRecords: sleepRecords,
            values: { day in [71, 59, 43, 23, 13].map { 100 + day * $0 % 251 } },
            output: { day, values in 60 + 0.04 * Double(values[day - 1][0]) + Double(day * 13 % 17) / 20 }
        )
        let clock = ContinuousClock()
        let start = clock.now
        let report = try #require(await application.discover(asOf: fixture.cutoff, timeZone: fixture.timeZone))
        print("Maximum discovery family: \(report.candidates.count) configurations in \(start.duration(to: clock.now))")
        #expect(report.candidates.count == 132)
        #expect(report.omittedInputCount == 1)
        #expect(report.findings.count <= 5)
        #expect(Set(report.candidates.map(\.configuration.output)) == [
            fixture.output, .health(metric: .sleepAnalysis, sourceBundleIdentifier: sleep.bundleIdentifier)
        ])
        #expect(report.candidates.allSatisfy {
            let configuration = $0.configuration
            let modeled = configuration.inputs + configuration.adjustmentInputs
            return !modeled.contains(inputs[4]) && configuration.history == .last365Days
        })

        let repeated = try #require(await application.discover(asOf: fixture.cutoff, timeZone: fixture.timeZone))
        #expect(repeated.candidates.map(\.configuration) == report.candidates.map(\.configuration))
        #expect(repeated.candidates.map(\.adjustedPValue) == report.candidates.map(\.adjustedPValue))
        #expect(repeated.findings.map(\.id) == report.findings.map(\.id))
    }

    @Test func requiresSourceResolutionAndKeepsTheResolvedSourceAndExactCutoff() async throws {
        let fixture = DiscoveryHistory()
        let alternate = HealthMeasurement.Source(name: "Another watch", bundleIdentifier: "fixture.alternate")
        let future = fixture.date(395).addingTimeInterval(18 * 3_600)
        let records = [
            HealthMeasurement(
                id: UUID(), metric: .restingHeartRate, value: 120, unit: .beatsPerMinute,
                startDate: fixture.date(100), endDate: fixture.date(100), source: alternate
            ),
            HealthMeasurement(
                id: UUID(), metric: .restingHeartRate, value: 150, unit: .beatsPerMinute,
                startDate: future, endDate: future, source: fixture.source
            )
        ]
        let (application, inputs) = try await fixture.application(
            days: 395, inputNames: ["Caffeine"], recordsInputsFrom: 33, additionalRecords: records, excluding: { $0 == 395 },
            values: { [100 + $0 * 71 % 251] },
            output: { day, values in 60 + 0.04 * Double(values[day - 1][0]) + Double(day * 13 % 17) / 20 }
        )
        let ambiguous = try #require(await application.discover(asOf: fixture.cutoff, timeZone: fixture.timeZone))
        #expect(ambiguous.status == .chooseOutputSource)
        #expect(ambiguous.candidates.isEmpty)
        try application.healthMeasurements.setPreferredSource(fixture.source.bundleIdentifier, for: .restingHeartRate)
        let report = try #require(await application.discover(asOf: fixture.cutoff, timeZone: fixture.timeZone))
        let finding = try #require(report.findings.first { $0.configuration.behaviorWindow == .precedingDay })
        #expect(finding.configuration.output == fixture.output)
        #expect(finding.completed.result.coverage.lastDate == fixture.date(394))
        #expect(finding.completed.result.observations.allSatisfy { $0.outputValue < 100 })
        #expect(finding.completed.result.inspection?.selectedOutputSourceIdentifier == fixture.source.bundleIdentifier)
        #expect(finding.completed.result.inspection?.unpairedOutputs.first?.missingInputs.first?.date == fixture.date(30))
        #expect(finding.completed.result.outputEvidence.filter { !$0.paired }.count == 3)
        try application.healthMeasurements.setPreferredSource(alternate.bundleIdentifier, for: .restingHeartRate)
        let pinnedSource = try #require(await application.discover(
            asOf: fixture.cutoff, timeZone: fixture.timeZone, enabledSeries: [inputs[0], fixture.output]
        ))
        #expect(pinnedSource.findings.map(\.configuration) == report.findings.map(\.configuration))
    }

    @Test(arguments: [10, 120, 395])
    func identifiesWhyWithoutReportingAResult(days: Int) async throws {
        let fixture = DiscoveryHistory()
        var noise = DiscoveryNoise(seed: 676)
        let errors = noise.series(count: days + 1, dependence: 0.80)
        let (application, _) = try await fixture.application(
            days: days, inputNames: ["Caffeine"], values: { [100 + $0 * 71 % 251] },
            output: { day, values in
                let signal = days < 395 ? 0.04 * Double(values[day - 1][0]) : 0
                return 70 + signal + errors[day]
            }
        )
        let cutoff = fixture.date(days).addingTimeInterval(12 * 3_600)
        let report = try #require(await application.discover(asOf: cutoff, timeZone: fixture.timeZone))
        let expected: DiscoveryReport.Status = switch days {
        case 10: .insufficientModelEvidence
        case 120: .insufficientBlockEvidence
        default: .noFindings
        }
        #expect(report.status == expected)
        #expect(report.findings.isEmpty)
    }

}

private struct DiscoveryHistory {
    let source = HealthMeasurement.Source(name: "Synthetic watch", bundleIdentifier: "fixture.discovery")
    let first = Date(timeIntervalSince1970: 1_704_067_200)
    let timeZone = TimeZone(secondsFromGMT: 0)!
    let locale = Locale(identifier: "en_US_POSIX")

    var cutoff: Date { date(395).addingTimeInterval(12 * 3_600) }
    var output: AnalysisSeriesID { .health(metric: .restingHeartRate, sourceBundleIdentifier: source.bundleIdentifier) }

    func date(_ day: Int) -> Date { first.addingTimeInterval(Double(day) * 86_400) }

    @MainActor
    func application(
        days: Int, inputNames: [String], storeURL: URL? = nil, recordsInputsFrom: Int = 0,
        additionalRecords: [HealthMeasurement] = [], excluding: (Int) -> Bool = { _ in false },
        values: (Int) -> [Int], output: (Int, [[Int]]) -> Double
    ) async throws -> (HealthAnalysisApplication, [AnalysisSeriesID]) {
        let inputs = (0..<days).map(values)
        let records = (1...days).filter { !excluding($0) }.map { day in measurement(day, bpm: output(day, inputs)) }
        let application = HealthAnalysisApplication(
            healthSource: DiscoverySource(records: records + additionalRecords), savedAnalysesStoreURL: storeURL
        )
        let quantities = try inputNames.map { name in
            try application.manualLog.createQuantity(
                name: name, unit: name == "Caffeine" ? "mg" : "units",
                defaultValue: 0, startsOn: ManualLogDay(date(recordsInputsFrom), timeZone: timeZone)
            )
        }
        for (index, row) in inputs.enumerated() where index >= recordsInputsFrom {
            let day = ManualLogDay(date(index), timeZone: timeZone)
            for (value, quantity) in zip(row, quantities) {
                application.manualLog.editQuantity(quantity.id, on: day, text: String(value), locale: locale)
            }
        }
        await application.healthMeasurements.refresh()
        return (application, quantities.map { .manualQuantity($0.id) })
    }

    func measurement(_ day: Int, bpm: Double) -> HealthMeasurement {
        let anchor = date(day).addingTimeInterval(9 * 3_600)
        return HealthMeasurement(
            id: UUID(), metric: .restingHeartRate, value: bpm, unit: .beatsPerMinute,
            startDate: anchor, endDate: anchor, source: source
        )
    }
}

private struct DiscoverySource: HealthMeasurementSource {
    let records: [HealthMeasurement]
    func requestReadAccess() async throws {}
    func readChanges(
        after anchors: [String: Data], includingPreviouslySaved: Bool
    ) async throws -> [HealthMeasurementChanges] {
        [.init(queryID: "restingHeartRate", anchor: Data([1]), added: records)]
    }
}


private extension DiscoveryCandidate {
    var adjustedPValue: Double? {
        if case .tested(let adjustedPValue) = outcome { return adjustedPValue }
        return nil
    }
}

private struct DiscoveryNoise {
    var seed: UInt64

    mutating func series(count: Int, dependence: Double) -> [Double] {
        var prior = 0.0
        return (0..<count).map { _ in
            let gaussian = sqrt(-2 * log(uniform())) * cos(2 * .pi * uniform())
            prior = dependence * prior + sqrt(1 - dependence * dependence) * gaussian
            return prior
        }
    }

    private mutating func uniform() -> Double {
        seed &+= 0x9e37_79b9_7f4a_7c15
        var bits = seed
        bits = (bits ^ (bits >> 30)) &* 0xbf58_476d_1ce4_e5b9
        bits = (bits ^ (bits >> 27)) &* 0x94d0_49bb_1331_11eb
        bits ^= bits >> 31
        return (Double(bits >> 11) + 0.5) / 9_007_199_254_740_992
    }
}
