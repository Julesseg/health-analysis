import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct AdjustedAnalysisTests {
    @Test func accountsForRecordedConfoundingInOneJointAnalysis() async throws {
        let (app, ids) = try await prepare(
            history: factorialHistory(), units: ["mg", "g", "h", "mg"], reopen: true
        )
        let unadjusted = try app.analyze(configuration(inputs: [ids[0]]))
        let raw = try #require(unadjusted.estimates.first)
        #expect(abs(raw.difference - 6) < 0.05)

        #expect(app.analysisAdjustmentSuggestions(excluding: Array(ids.prefix(3))).map(\.id) == [ids[3]])
        let result = try app.analyze(configuration(inputs: Array(ids.prefix(3)), adjustments: [ids[3]]))
        #expect(result.model == .numericLinearV1)
        #expect(result.outputSource?.bundleIdentifier == "fixture.adjusted")
        #expect(result.modeledInputs.map(\.series) == ids.map(AnalysisSeriesID.manualQuantity))
        #expect(result.modeledInputs.map(\.role) == [.input, .input, .input, .adjustment])
        #expect(result.modeledInputs.map(\.unit) == ["mg", "g", "h", "mg"])
        #expect(result.modeledInputs.map(\.defaultDayCount) == [0, 0, 0, 0])
        #expect(result.coverage.usableDates.count == 128)

        let expected = [0.0, 1.5, -0.4, 6.0]
        #expect(result.estimates.map(\.input) == ids.map(AnalysisSeriesID.manualQuantity))
        for (estimate, truth) in zip(result.estimates, expected) {
            #expect(abs(estimate.difference - truth) < 0.05)
            #expect(estimate.interval.contains(truth))
        }
        #expect(result.estimates.map(\.inputIncrement) == [100, 1, 1, 100])
        #expect(result.estimates.first?.finding == .nearZero)
        #expect(result.evidence.grade == .low)

        let withoutAdjustment = try app.analyze(configuration(inputs: Array(ids.prefix(3))))
        #expect(abs(try #require(withoutAdjustment.estimates.first).difference - 6) < 0.05)
    }

    @Test(arguments: [0.0, 0.1])
    func distinguishesCollinearityFromAnEstimatedAssociation(perturbation: Double) async throws {
        let history = factorialHistory().enumerated().map { index, row in
            var row = row
            let caffeine = row.amounts[0]!
            let other = row.amounts[1]!
            row.amounts[3] = 2 * caffeine + 10 * other + (index & 16 == 0 ? -perturbation : perturbation)
            return row
        }
        let (app, ids) = try await prepare(history: history, units: ["mg", "g", "h", "mg"])
        let expected = Set([ids[0], ids[1], ids[3]].map(AnalysisSeriesID.manualQuantity))
        for config in [
            configuration(inputs: Array(ids.prefix(3)), adjustments: [ids[3]]),
            configuration(inputs: Array(ids.reversed()))
        ] {
            let result = try app.analyze(config)
            #expect(result.estimates.isEmpty)
            #expect(result.evidence.grade == .insufficient)
            #expect(result.evidence.reasons == [.collinearInputs(expected)])
        }
    }

    @Test func identifiesDefaultOnlyAndLowVariationInputs() async throws {
        let history = factorialHistory().enumerated().map { index, row in
            var row = row
            row.amounts[1] = 6
            row.amounts[2] = nil
            row.amounts[3] = 150 + Double(index % 3)
            return row
        }
        let (app, ids) = try await prepare(history: history, units: ["mg", "g", "h", "mg"])
        let result = try app.analyze(configuration(inputs: Array(ids.prefix(3)), adjustments: [ids[3]]))
        #expect(result.coverage.usableDates.count == 128)
        #expect(result.modeledInputs.map(\.defaultDayCount) == [0, 0, 128, 0])
        #expect(result.evidence.defaultDayCount == 128)
        #expect(result.evidence.grade == .insufficient)
        #expect(result.evidence.reasons.contains(.defaultOnlyInputs([.manualQuantity(ids[2])])))
        #expect(result.evidence.reasons.contains(.lowVariationInputs([.manualQuantity(ids[1]), .manualQuantity(ids[3])])))
        #expect(result.estimates.isEmpty)
    }

    @Test func reportsHowMuchJointHistoryTheSelectedModelNeeds() async throws {
        let (app, ids) = try await prepare(history: Array(factorialHistory().prefix(59)), units: ["mg", "g", "h", "mg"])
        let result = try app.analyze(configuration(inputs: Array(ids.prefix(3)), adjustments: [ids[3]]))
        #expect(result.coverage.usableDates.count == 59)
        #expect(result.evidence.reasons == [.inadequateJointCoverage(minimumDays: 60)])
        #expect(result.estimates.isEmpty)
    }

    @Test func intervalsCoverAdjustedCoefficientsWithSerialDependenceAndCalendarGaps() async throws {
        let trials = 96
        var independentHits = [0, 0]
        var dependentHits = [0, 0]
        var independentWidth = 0.0
        var dependentWidth = 0.0
        for trial in 0..<trials {
            let slope = trial.isMultiple(of: 2) ? 0.0 : -1.5
            let truths = [slope, 1.8]
            let independent = try await simulate(slope: slope, seed: UInt64(1_500 + trial), persistence: 0)
            let dependent = try await simulate(slope: slope, seed: UInt64(1_500 + trial), persistence: 0.8)
            #expect(dependent.coverage.missingDays == 42)
            for (index, estimateIndex) in [0, 2].enumerated() {
                let iid = try #require(independent.estimates.dropFirst(estimateIndex).first?.interval)
                let serial = try #require(dependent.estimates.dropFirst(estimateIndex).first?.interval)
                if iid.contains(truths[index]) { independentHits[index] += 1 }
                if serial.contains(truths[index]) { dependentHits[index] += 1 }
                independentWidth += iid.upperBound - iid.lowerBound
                dependentWidth += serial.upperBound - serial.lowerBound
            }
        }
        for hits in independentHits {
            #expect((0.88...0.99).contains(Double(hits) / Double(trials)))
        }
        for hits in dependentHits {
            #expect((0.86...0.99).contains(Double(hits) / Double(trials)))
        }
        #expect(dependentWidth / independentWidth > 1.35)
    }

    private func simulate(slope: Double, seed: UInt64, persistence: Double) async throws -> AnalysisResult {
        var random = AdjustedGaussianSequence(seed: seed)
        var state = (0..<4).map { _ in random.next() }
        let scale = sqrt(1 - persistence * persistence)
        let history = (0..<252).map { index in
            for term in state.indices {
                state[term] = persistence * state[term] + scale * random.next()
            }
            let caffeine = 200 + 32 * (0.65 * state[0] + sqrt(1 - 0.65 * 0.65) * state[1])
            let duration = 8 + 1.1 * state[2]
            let adjustment = 200 + 40 * state[0]
            let bpm = 70 + slope * (caffeine - 200) / 100 + 0.8 * (duration - 8)
                + 1.8 * (adjustment - 200) / 100 + 1.5 * state[3]
            return Day(amounts: [caffeine, duration, adjustment], bpm: index % 17 >= 14 ? nil : bpm)
        }
        let (app, ids) = try await prepare(history: history, units: ["mg", "h", "mg"])
        return try app.analyze(configuration(inputs: Array(ids.prefix(2)), adjustments: [ids[2]]))
    }

    struct Day {
        var amounts: [Double?]
        var bpm: Double?
    }

    private func factorialHistory() -> [Day] {
        (0..<128).map { index in
            func sign(_ bit: Int) -> Double { index & (1 << bit) == 0 ? -1 : 1 }
            let confounder = sign(0)
            let caffeine = 200 + 40 * confounder + 20 * sign(1)
            let other = 6 + sign(2)
            let duration = 8 + sign(3)
            let bpm = 65 + 3 * confounder + 1.5 * (other - 6) - 0.4 * (duration - 8) + 0.18 * sign(4)
            return Day(amounts: [caffeine, other, duration, 150 + 50 * confounder], bpm: bpm)
        }
    }

    func configuration(inputs: [UUID], adjustments: [UUID] = []) -> AnalysisConfiguration {
        .init(
            output: .health(metric: .restingHeartRate, sourceBundleIdentifier: "fixture.adjusted"),
            inputs: inputs.map(AnalysisSeriesID.manualQuantity),
            adjustmentInputs: adjustments.map(AnalysisSeriesID.manualQuantity),
            timeZone: utc
        )
    }

    private let utc = TimeZone(secondsFromGMT: 0)!
    private let locale = Locale(identifier: "en_US_POSIX")

    func prepare(
        history: [Day], units: [String], reopen: Bool = false, defaults: [Decimal]? = nil, savedURL: URL? = nil
    ) async throws -> (HealthAnalysisApplication, [UUID]) {
        let first = Date(timeIntervalSince1970: 1_735_689_600)
        func date(_ index: Int) -> Date { first.addingTimeInterval(Double(index) * 86_400) }
        let records = history.enumerated().compactMap { index, row in
            row.bpm.map { bpm in
                let anchor = date(index + 1).addingTimeInterval(32_400)
                return HealthMeasurement(
                    id: UUID(), metric: .restingHeartRate, value: bpm, unit: .beatsPerMinute,
                    startDate: anchor, endDate: anchor,
                    source: .init(name: "Fixture watch", bundleIdentifier: "fixture.adjusted")
                )
            }
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { if reopen { try? FileManager.default.removeItem(at: directory) } }
        let healthURL = reopen ? directory.appending(path: "health.json") : nil
        let logURL = reopen ? directory.appending(path: "log.json") : nil
        let app = HealthAnalysisApplication(
            healthSource: Source(records: records), healthHistoryStoreURL: healthURL,
            manualLogStoreURL: logURL, savedAnalysesStoreURL: savedURL
        )
        let quantities = try units.enumerated().map { index, unit in
            try app.manualLog.createQuantity(
                name: "Quantity \(index + 1)", unit: unit, defaultValue: defaults?[index] ?? 0,
                startsOn: ManualLogDay(first, timeZone: utc)
            )
        }
        for (index, row) in history.enumerated() {
            for (quantity, value) in zip(quantities, row.amounts) {
                guard let value else { continue }
                app.manualLog.editQuantity(
                    quantity.id, on: ManualLogDay(date(index), timeZone: utc), text: String(value), locale: locale
                )
            }
        }
        await app.healthMeasurements.refresh()
        let ids = quantities.map(\.id)
        if reopen {
            return (HealthAnalysisApplication(healthHistoryStoreURL: healthURL, manualLogStoreURL: logURL), ids)
        }
        return (app, ids)
    }

    private struct Source: HealthMeasurementSource {
        let records: [HealthMeasurement]

        func requestReadAccess() async throws {}

        func readChanges(
            after anchors: [String: Data], includingPreviouslySaved: Bool
        ) async throws -> [HealthMeasurementChanges] {
            [.init(queryID: "restingHeartRate", anchor: Data([1]), added: records)]
        }
    }
}

struct AdjustedGaussianSequence {
    var seed: UInt64

    mutating func next() -> Double {
        sqrt(-2 * log(uniform())) * cos(2 * .pi * uniform())
    }

    private mutating func uniform() -> Double {
        seed = 2_862_933_555_777_941_757 &* seed &+ 3_037_000_493
        return (Double(seed >> 11) + 0.5) / 9_007_199_254_740_992
    }
}
