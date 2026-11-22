import Foundation

public enum AnalysisModel: String, Codable, Hashable, Sendable {
    case caffeineLinearV1
    case numericLinearV1
    case countLogLinearV1
}

public struct AnalysisModeledInput: Codable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable {
        case input
        case adjustment
    }

    public var id: AnalysisSeriesID { series }
    public let series: AnalysisSeriesID
    public let name: String
    public let unit: String
    public let role: Role
    public let defaultDayCount: Int

    public internal(set) var kind: AnalysisVariable.Kind? = nil

    var isMilligramQuantity: Bool { unit.lowercased() == "mg" }
    var inputIncrement: Double { isMilligramQuantity ? 100 : 1 }
}

struct NumericAnalysis {
    let model: AnalysisModel
    let estimates: [AnalysisEstimate]
    let evidence: AnalysisEvidence

    static func assess(
        _ observations: [AnalysisObservation], inputs: [AnalysisModeledInput],
        coverage: AnalysisCoverage, calendar: Calendar
    ) -> Self {
        if inputs.count == 1, inputs.first?.isMilligramQuantity == true {
            let legacy = NumericAssociation.assess(observations, coverage: coverage, calendar: calendar)
            return Self(model: .caffeineLinearV1, estimates: [legacy.estimate].compactMap { $0 }, evidence: legacy.evidence)
        }

        let count = observations.count
        let defaultDays = observations.count { row in row.inputs.contains { $0.origin != .observation } }
        func result(
            _ grade: AnalysisEvidence.Grade, _ reasons: [AnalysisEvidence.Reason],
            estimates: [AnalysisEstimate] = [], lagDays: Int? = nil
        ) -> Self {
            Self(model: .numericLinearV1, estimates: estimates, evidence: AnalysisEvidence(
                grade: grade, reasons: reasons, defaultDayCount: defaultDays, dependenceLagDays: lagDays
            ))
        }

        let minimumDays = max(42, 12 * (inputs.count + 1))
        guard count >= minimumDays else {
            return result(.insufficient, [.inadequateJointCoverage(minimumDays: minimumDays)])
        }
        let dayNumbers = observations.compactMap { calendar.ordinality(of: .day, in: .era, for: $0.outputDate) }
        let lagDays = CalendarHAC.defaultLagDays(for: count)
        let columns = inputs.indices.map { index in observations.map { $0.inputs[index].value } }
        let outputs = observations.map(\.outputValue)
        var defaultOnly: Set<AnalysisSeriesID> = []
        var lowVariation: Set<AnalysisSeriesID> = []
        for (index, input) in inputs.enumerated() {
            let observed = observations.compactMap { row in
                let value = row.inputs[index]
                return value.origin == .observation ? value.value : nil
            }
            if observed.isEmpty {
                defaultOnly.insert(input.series)
            } else if !hasVariation(columns[index], input: input) || !hasVariation(observed, input: input) {
                lowVariation.insert(input.series)
            }
        }
        var limitations: [AnalysisEvidence.Reason] = []
        if !defaultOnly.isEmpty { limitations.append(.defaultOnlyInputs(defaultOnly)) }
        if !lowVariation.isEmpty { limitations.append(.lowVariationInputs(lowVariation)) }
        guard limitations.isEmpty else { return result(.insufficient, limitations) }

        func collinear(_ indices: Set<Int>) -> Self {
            result(.insufficient, [.collinearInputs(Set(indices.map { inputs[$0].series }))])
        }
        let fit: LinearAssociationFit
        do {
            fit = try LinearAssociationFit(columns: columns, outputs: outputs, dayNumbers: dayNumbers, lagDays: lagDays)
        } catch .dependentColumns(let indices) {
            return collinear(indices)
        } catch {
            return result(.insufficient, [.uncertaintyUnavailable])
        }
        let inflation = fit.varianceInflation
        let collinearIndices = Set(inflation.indices.filter { inflation[$0] >= 20 })
        guard collinearIndices.isEmpty else { return collinear(collinearIndices) }

        var estimates: [AnalysisEstimate] = []
        for (index, input) in inputs.enumerated() {
            var contrast = Array(repeating: 0.0, count: inputs.count)
            contrast[index] = input.inputIncrement
            guard let estimate = fit.estimate(contrast: contrast) else {
                return result(.insufficient, [.uncertaintyUnavailable])
            }
            let interval = (estimate.difference - estimate.halfWidth)...(estimate.difference + estimate.halfWidth)
            estimates.append(AnalysisEstimate(
                input: input.series, inputIncrement: input.inputIncrement,
                difference: estimate.difference, interval: interval,
                finding: finding(interval, nearZero: input.isMilligramQuantity ? 1 : nil)
            ))
        }
        limitations.append(.adjustedModelLimitations)
        if count < 90 { limitations.append(.limitedHistory) }
        if Double(count) / Double(count + coverage.missingDays) < 0.75 { limitations.append(.sparseCoverage) }
        if Double(defaultDays) / Double(count) > 0.25 { limitations.append(.manyDefaults) }
        if estimates.contains(where: { $0.finding == .uncertain }) { limitations.append(.indeterminateInterval) }
        return result(.low, limitations, estimates: estimates, lagDays: lagDays)
    }

    static func hasVariation(_ values: [Double], input: AnalysisModeledInput) -> Bool {
        if input.kind == .tracked(.count) { return CountAnalysis.supportingVariation(values) }
        guard !values.isEmpty else { return false }
        let sorted = values.sorted()
        let upper = sorted[3 * sorted.count / 4]
        let lower = sorted[sorted.count / 4]
        let spread = upper - lower
        let resolution = 64 * max(upper.ulp, lower.ulp)
        return spread > resolution && (!input.isMilligramQuantity || spread >= 20)
    }

    static func finding(_ interval: ClosedRange<Double>, nearZero: Double?) -> AnalysisEstimate.Finding {
        if let nearZero, interval.lowerBound >= -nearZero, interval.upperBound <= nearZero { return .nearZero }
        if interval.lowerBound > 0 { return .higher }
        if interval.upperBound < 0 { return .lower }
        return .uncertain
    }
}
