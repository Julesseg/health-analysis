import Foundation

enum BinaryAnalysis {
    static func assess(
        _ observations: [AnalysisObservation], inputs: [AnalysisModeledInput],
        coverage: AnalysisCoverage, calendar: Calendar
    ) -> NumericAnalysis {
        let count = observations.count
        let defaultDays = observations.count { row in
            row.outputOrigin != .observation || row.inputs.contains { $0.origin != .observation }
        }
        func result(
            _ grade: AnalysisEvidence.Grade, _ reasons: [AnalysisEvidence.Reason],
            estimates: [AnalysisEstimate] = [], lagDays: Int? = nil
        ) -> NumericAnalysis {
            NumericAnalysis(model: .binaryLogisticV1, estimates: estimates, interaction: nil, evidence: AnalysisEvidence(
                grade: grade, reasons: reasons, defaultDayCount: defaultDays, dependenceLagDays: lagDays
            ))
        }

        let minimumDays = max(42, 12 * (inputs.count + 1))
        guard count >= minimumDays else {
            return result(.insufficient, [.inadequateJointCoverage(minimumDays: minimumDays)])
        }
        let outputs = observations.map(\.outputValue)
        let observedOutputs = observations.compactMap { $0.outputOrigin == .observation ? $0.outputValue : nil }
        guard !observedOutputs.isEmpty else { return result(.insufficient, [.defaultOnlyOutput]) }
        guard Set(observedOutputs).count > 1 else { return result(.insufficient, [.lowVariationOutput]) }
        guard BinaryEvent.hasSupport(observedOutputs, minimum: BinaryEvent.minimumSupport * inputs.count) else {
            return result(.insufficient, [.sparseObservedBinaryOutput])
        }

        let columns = inputs.indices.map { index in observations.map { $0.inputs[index].value } }
        var limitations = NumericAnalysis.inputLimitations(observations, inputs: inputs, columns: columns)
        guard limitations.isEmpty else { return result(.insufficient, limitations) }

        func collinear(_ indices: Set<Int>) -> NumericAnalysis {
            result(.insufficient, [.collinearInputs(Set(indices.map { inputs[$0].series }))])
        }
        do {
            let inflation = try OrthogonalDesign(columns: columns).varianceInflation
            let collinearIndices = Set(inflation.indices.filter { inflation[$0] >= 20 })
            guard collinearIndices.isEmpty else { return collinear(collinearIndices) }
        } catch .dependentColumns(let indices) {
            return collinear(indices)
        } catch {
            return result(.insufficient, [.binaryModelUnavailable])
        }

        if let reason = sparseCombinations(observations, inputs: inputs, includesOutput: true) {
            return result(.insufficient, [reason])
        }

        let dayNumbers = observations.compactMap { calendar.ordinality(of: .day, in: .era, for: $0.outputDate) }
        let lagDays = CalendarHAC.defaultLagDays(for: count)
        guard dayNumbers.count == count, zip(dayNumbers, dayNumbers.dropFirst()).allSatisfy(<),
              let fit = BinaryEventFit(columns: columns, events: outputs) else {
            return result(.insufficient, [.binaryModelUnavailable])
        }

        var estimates: [AnalysisEstimate] = []
        for (index, input) in inputs.enumerated() {
            guard let comparisons = comparisons(for: input, at: index, in: observations) else {
                return result(.insufficient, [.binaryContrastUnavailable([input.series])])
            }
            guard let estimate = fit.probabilityDifference(
                varying: index, comparisons: comparisons, dayNumbers: dayNumbers, lagDays: lagDays
            ) else { return result(.insufficient, [.uncertaintyUnavailable]) }
            estimates.append(AnalysisEstimate(
                input: input.series, inputIncrement: input.inputIncrement, difference: estimate.difference,
                interval: estimate.interval, finding: NumericAnalysis.finding(estimate.interval, nearZero: nil),
                scale: .probabilityDifference
            ))
        }
        limitations.append(.binaryModelLimitations)
        if count < 90 { limitations.append(.limitedHistory) }
        if Double(count) / Double(count + coverage.missingDays) < 0.75 { limitations.append(.sparseCoverage) }
        if Double(defaultDays) / Double(count) > 0.25 { limitations.append(.manyDefaults) }
        if estimates.contains(where: { $0.finding == .uncertain }) { limitations.append(.indeterminateInterval) }
        return result(.low, limitations, estimates: estimates, lagDays: lagDays)
    }

    private static func comparisons(
        for input: AnalysisModeledInput, at column: Int, in observations: [AnalysisObservation]
    ) -> [BinaryEventFit.Comparison]? {
        if input.kind == .tracked(.yesNo) {
            return observations.indices.map {
                .init(rowIndex: $0, lower: BinaryEvent.encode(false), upper: BinaryEvent.encode(true))
            }
        }

        let samples = observations.map { $0.inputs[column] }
        let recorded = samples.filter { $0.origin == .observation }.map(\.value)
        guard let minimum = recorded.min(), let maximum = recorded.max() else { return nil }
        let increment = input.inputIncrement
        let eligible = samples.indices.filter {
            let value = samples[$0].value
            return value >= minimum && value + increment <= maximum
        }
        guard eligible.count(where: { samples[$0].origin == .observation }) >= BinaryEvent.minimumSupport else {
            return nil
        }
        return eligible.map {
            let lower = samples[$0].value
            return .init(rowIndex: $0, lower: lower, upper: lower + increment)
        }
    }

    static func sparseCombinations(
        _ observations: [AnalysisObservation], inputs: [AnalysisModeledInput], includesOutput: Bool = false
    ) -> AnalysisEvidence.Reason? {
        let binaryInputs = inputs.indices.filter { inputs[$0].kind == .tracked(.yesNo) }
        let dimension = binaryInputs.count + (includesOutput ? 1 : 0)
        guard dimension >= 2 else { return nil }
        let recordedCombinations = observations.compactMap { row -> [Double]? in
            guard binaryInputs.allSatisfy({ row.inputs[$0].origin == .observation }),
                  !includesOutput || row.outputOrigin == .observation else { return nil }
            let predictorValues = binaryInputs.map { row.inputs[$0].value }
            return includesOutput ? predictorValues + [row.outputValue] : predictorValues
        }
        let frequencies = Dictionary(recordedCombinations.map { ($0, 1) }, uniquingKeysWith: +)
        if dimension < Int.bitWidth - 1, frequencies.count == 1 << dimension,
           frequencies.values.allSatisfy({ $0 >= BinaryEvent.minimumSupport }) {
            return nil
        }
        return .sparseBinaryCombinations(Set(binaryInputs.map { inputs[$0].series }))
    }
}
