import Foundation

enum CountAnalysis {
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
            NumericAnalysis(model: .countLogLinearV1, estimates: estimates, interaction: nil, evidence: AnalysisEvidence(
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
        guard observedOutputs.count >= 12, observedOutputs.count(where: { $0 > 0 }) >= 6,
              supportingVariation(observedOutputs) else {
            return result(.insufficient, [.sparseObservedCountOutput])
        }

        guard let columns = NumericAnalysis.inputColumns(observations, inputs: inputs) else {
            return result(.insufficient, [.uncertaintyUnavailable])
        }
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
            return result(.insufficient, [.countModelUnavailable])
        }

        let dayNumbers = observations.compactMap { calendar.ordinality(of: .day, in: .era, for: $0.outputDate) }
        let lagDays = CalendarHAC.defaultLagDays(for: count)
        guard dayNumbers.count == count, zip(dayNumbers, dayNumbers.dropFirst()).allSatisfy(<),
              let fit = PoissonMeanFit(columns: columns, counts: outputs) else {
            return result(.insufficient, [.countModelUnavailable])
        }

        var estimates: [AnalysisEstimate] = []
        for (index, input) in inputs.enumerated() {
            var contrast = Array(repeating: 0.0, count: inputs.count)
            contrast[index] = input.inputIncrement
            guard let log = fit.logContrast(contrast, dayNumbers: dayNumbers, lagDays: lagDays),
                  log.estimate + log.halfWidth < 700 else {
                return result(.insufficient, [.uncertaintyUnavailable])
            }
            let interval = expm1(log.estimate - log.halfWidth)...expm1(log.estimate + log.halfWidth)
            estimates.append(AnalysisEstimate(
                input: input.series, inputIncrement: input.inputIncrement, difference: expm1(log.estimate),
                interval: interval, finding: NumericAnalysis.finding(interval, nearZero: nil),
                scale: .proportionalCountChange
            ))
        }
        limitations.append(.countModelLimitations)
        if inputs.contains(where: { $0.kind?.ratingThreshold != nil }) { limitations.append(.ratingThresholdLimitations) }
        if count < 90 { limitations.append(.limitedHistory) }
        if Double(count) / Double(count + coverage.missingDays) < 0.75 { limitations.append(.sparseCoverage) }
        if Double(defaultDays) / Double(count) > 0.25 { limitations.append(.manyDefaults) }
        if estimates.contains(where: { $0.finding == .uncertain }) { limitations.append(.indeterminateInterval) }
        return result(.low, limitations, estimates: estimates, lagDays: lagDays)
    }

    static func supportingVariation(_ values: [Double]) -> Bool {
        let frequencies = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return values.count - (frequencies.values.max() ?? 0) >= 6
    }
}
