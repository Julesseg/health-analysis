import Foundation

public enum AnalysisModel: String, Codable, Hashable, Sendable {
    case caffeineLinearV1
    case numericLinearV1
    case countLogLinearV1
    case numericInteractionV1
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

    func hasVariation(from lower: Double, to upper: Double) -> Bool {
        let spread = upper - lower
        let resolution = 64 * max(upper.ulp, lower.ulp)
        return spread > resolution && (!isMilligramQuantity || spread >= 20)
    }
}

struct NumericAnalysis {
    let model: AnalysisModel
    let estimates: [AnalysisEstimate]
    let interaction: AnalysisInteractionEstimate?
    let evidence: AnalysisEvidence

    static func assess(
        _ observations: [AnalysisObservation], inputs: [AnalysisModeledInput],
        coverage: AnalysisCoverage, calendar: Calendar,
        behaviorWindow: AnalysisBehaviorWindow = .precedingDay, practicalDifference: Double = 1,
        interaction: AnalysisInteraction? = nil
    ) -> Self {
        if interaction == nil, inputs.count == 1, inputs.first?.isMilligramQuantity == true {
            let legacy = NumericAssociation.assess(
                observations, coverage: coverage, calendar: calendar,
                behaviorWindow: behaviorWindow, practicalDifference: practicalDifference
            )
            return Self(
                model: .caffeineLinearV1, estimates: [legacy.estimate].compactMap { $0 },
                interaction: nil, evidence: legacy.evidence
            )
        }

        let count = observations.count
        let defaultDays = observations.count { row in row.inputs.contains { $0.origin != .observation } }
        func result(
            _ grade: AnalysisEvidence.Grade, _ reasons: [AnalysisEvidence.Reason],
            estimates: [AnalysisEstimate] = [], interactionEstimate: AnalysisInteractionEstimate? = nil, lagDays: Int? = nil
        ) -> Self {
            Self(
                model: interaction == nil ? .numericLinearV1 : .numericInteractionV1,
                estimates: estimates, interaction: interactionEstimate,
                evidence: AnalysisEvidence(
                    grade: grade, reasons: reasons, defaultDayCount: defaultDays, dependenceLagDays: lagDays
                )
            )
        }

        let parameterCount = inputs.count + (interaction == nil ? 1 : 2)
        let minimumDays = max(42, 12 * parameterCount)
        guard count >= minimumDays else {
            return result(.insufficient, [.inadequateJointCoverage(minimumDays: minimumDays)])
        }
        guard coverage.nonOverlappingWindowCount >= 6 else {
            return result(.insufficient, [.limitedNonOverlappingWindows])
        }
        let dayNumbers = observations.compactMap { calendar.ordinality(of: .day, in: .era, for: $0.outputDate) }
        let lagDays = CalendarHAC.defaultLagDays(for: count)
        var columns = inputs.indices.map { index in observations.map { $0.inputs[index].value } }
        let outputs = observations.map(\.outputValue)
        var defaultOnly: Set<AnalysisSeriesID> = []
        var lowVariation: Set<AnalysisSeriesID> = []
        for (index, input) in inputs.enumerated() {
            let observed = observations.compactMap { row in
                let value = row.inputs[index]
                return value.origin == .observation ? value.value : nil
            }
            let hasObservedDay = observations.contains { $0.inputs[index].hasObservedDay }
            if !hasObservedDay {
                defaultOnly.insert(input.series)
            } else if observed.isEmpty || !hasVariation(columns[index], input: input)
                        || !hasVariation(observed, input: input) {
                lowVariation.insert(input.series)
            }
        }
        var limitations: [AnalysisEvidence.Reason] = []
        if !defaultOnly.isEmpty { limitations.append(.defaultOnlyInputs(defaultOnly)) }
        if !lowVariation.isEmpty { limitations.append(.lowVariationInputs(lowVariation)) }
        guard limitations.isEmpty else { return result(.insufficient, limitations) }

        var columnInputs = inputs.map { Set([$0.series]) }
        var interactionDesign: NumericInteractionDesign?
        if let interaction {
            guard let focal = inputs.firstIndex(where: { $0.series == interaction.focal }),
                  let moderator = inputs.firstIndex(where: { $0.series == interaction.moderator }) else {
                return result(.insufficient, [.uncertaintyUnavailable])
            }
            switch NumericInteractionDesign.prepare(inputs: inputs, focal: focal, moderator: moderator, rows: observations) {
            case .supported(let design):
                interactionDesign = design
                columns.append(design.productColumn)
                columnInputs.append([interaction.focal, interaction.moderator])
            case .insufficient(let support):
                limitations.append(.poorlyRepresentedInteraction(support))
            }
        }

        func collinear(_ indices: Set<Int>) -> Self {
            result(.insufficient, [.collinearInputs(Set(indices.flatMap { columnInputs[$0] }))] + limitations)
        }
        let fit: LinearAssociationFit
        do {
            fit = try LinearAssociationFit(
                columns: columns, outputs: outputs, dayNumbers: dayNumbers,
                lagDays: lagDays, windowDays: behaviorWindow.dayCount
            )
        } catch .dependentColumns(let indices) {
            return collinear(indices)
        } catch {
            return result(.insufficient, limitations.isEmpty ? [.uncertaintyUnavailable] : limitations)
        }
        let inflation = fit.varianceInflation
        let collinearIndices = Set(inflation.indices.filter { inflation[$0] >= 20 })
        guard collinearIndices.isEmpty else { return collinear(collinearIndices) }
        guard limitations.isEmpty else { return result(.insufficient, limitations) }

        var estimates: [AnalysisEstimate] = []
        var maximumLag = lagDays
        for (index, input) in inputs.enumerated() {
            var contrast = Array(repeating: 0.0, count: columns.count)
            contrast[index] = input.inputIncrement
            guard let estimate = fit.estimate(contrast: contrast) else {
                return result(.insufficient, [.uncertaintyUnavailable])
            }
            let interval = (estimate.difference - estimate.halfWidth)...(estimate.difference + estimate.halfWidth)
            maximumLag = max(maximumLag, estimate.lagDays)
            estimates.append(AnalysisEstimate(
                input: input.series, inputIncrement: input.inputIncrement,
                difference: estimate.difference, interval: interval,
                finding: finding(interval, nearZero: input.isMilligramQuantity ? practicalDifference : nil),
                reference: interactionDesign?.reference(for: index)
            ))
        }
        let comparison = interactionDesign?.estimate(using: fit, practicalDifference: practicalDifference)
        if interactionDesign != nil, comparison == nil {
            return result(.insufficient, [.uncertaintyUnavailable])
        }
        if let comparison { maximumLag = max(maximumLag, comparison.lagDays) }
        limitations.append(.adjustedModelLimitations)
        if coverage.nonOverlappingWindowCount < count { limitations.append(.overlappingBehaviorWindows) }
        if count < 90 { limitations.append(.limitedHistory) }
        if Double(count) / Double(count + coverage.missingDays) < 0.75 { limitations.append(.sparseCoverage) }
        if Double(defaultDays) / Double(count) > 0.25 { limitations.append(.manyDefaults) }
        if estimates.contains(where: { $0.finding == .uncertain }) || comparison?.estimate.finding == .uncertain {
            limitations.append(.indeterminateInterval)
        }
        return result(.low, limitations, estimates: estimates, interactionEstimate: comparison?.estimate, lagDays: maximumLag)
    }

    static func hasVariation(_ values: [Double], input: AnalysisModeledInput) -> Bool {
        if input.kind == .tracked(.count) { return CountAnalysis.supportingVariation(values) }
        guard !values.isEmpty else { return false }
        let sorted = values.sorted()
        let upper = sorted[3 * sorted.count / 4]
        let lower = sorted[sorted.count / 4]
        return input.hasVariation(from: lower, to: upper)
    }

    static func finding(_ interval: ClosedRange<Double>, nearZero: Double?) -> AnalysisEstimate.Finding {
        if let nearZero, interval.lowerBound >= -nearZero, interval.upperBound <= nearZero { return .nearZero }
        if interval.lowerBound > 0 { return .higher }
        if interval.upperBound < 0 { return .lower }
        return .uncertain
    }
}
