import Foundation

public enum AnalysisModel: String, Codable, Hashable, Sendable {
    case caffeineLinearV1
    case numericLinearV1
    case countLogLinearV1
    case binaryLogisticV1
    case ratingThresholdLinearV1
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
    var inputIncrement: Double {
        if kind == .tracked(.timeOfDay) { return 60 }
        return isMilligramQuantity ? 100 : 1
    }

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
        interaction: AnalysisInteraction? = nil, ratingOutputThreshold: Int? = nil, outputIsClock: Bool = false
    ) -> Self {
        let usesClock = outputIsClock || inputs.contains { $0.kind == .tracked(.timeOfDay) }
        let usesRatings = ratingOutputThreshold != nil || inputs.contains { $0.kind?.ratingThreshold != nil }
        if !usesClock, !usesRatings, interaction == nil, inputs.count == 1, inputs.first?.isMilligramQuantity == true {
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
        let defaultDays = observations.count { row in
            (row.outputOrigin ?? .observation) != .observation || row.inputs.contains { $0.origin != .observation }
        }
        func result(
            _ grade: AnalysisEvidence.Grade, _ reasons: [AnalysisEvidence.Reason],
            estimates: [AnalysisEstimate] = [], interactionEstimate: AnalysisInteractionEstimate? = nil, lagDays: Int? = nil
        ) -> Self {
            Self(
                model: usesRatings ? .ratingThresholdLinearV1
                    : (interaction == nil ? .numericLinearV1 : .numericInteractionV1),
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
        let outputs: [Double]
        if let threshold = ratingOutputThreshold {
            outputs = observations.compactMap { RatingAnalysis.indicator($0.outputTrackingValue, threshold: threshold) }
            guard outputs.count == count else { return result(.insufficient, [.uncertaintyUnavailable]) }
            let recorded = zip(observations, outputs).compactMap { $0.outputOrigin == .observation ? $1 : nil }
            guard !recorded.isEmpty else { return result(.insufficient, [.defaultOnlyOutput]) }
            guard RatingAnalysis.hasSupport(recorded) else {
                return result(.insufficient, [.sparseObservedRatingOutput])
            }
        } else {
            outputs = observations.map(\.outputValue)
        }
        guard var columns = inputColumns(observations, inputs: inputs) else {
            return result(.insufficient, [.uncertaintyUnavailable])
        }
        var limitations = inputLimitations(observations, inputs: inputs, columns: columns)
        guard limitations.isEmpty else { return result(.insufficient, limitations) }

        if let reason = BinaryAnalysis.sparseCombinations(observations, inputs: inputs) {
            return result(.insufficient, [reason])
        }

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
                lagDays: lagDays, windowDays: behaviorWindow.dayCount, adjustsForResidualDependence: usesRatings
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
                finding: finding(
                    interval, nearZero: !usesClock && ratingOutputThreshold == nil && input.isMilligramQuantity ? practicalDifference : nil
                ),
                reference: interactionDesign?.reference(for: index),
                scale: outputIsClock ? .clockMinutesDifference : (ratingOutputThreshold == nil ? nil : .ratingThresholdProbabilityDifference)
            ))
        }
        let comparison = interactionDesign?.estimate(using: fit, practicalDifference: practicalDifference)
        if interactionDesign != nil, comparison == nil {
            return result(.insufficient, [.uncertaintyUnavailable])
        }
        if let comparison { maximumLag = max(maximumLag, comparison.lagDays) }
        limitations.append(.adjustedModelLimitations)
        if usesRatings { limitations.append(.ratingThresholdLimitations) }
        if coverage.nonOverlappingWindowCount < count { limitations.append(.overlappingBehaviorWindows) }
        if count < 90 { limitations.append(.limitedHistory) }
        if Double(count) / Double(count + coverage.missingDays) < 0.75 { limitations.append(.sparseCoverage) }
        if Double(defaultDays) / Double(count) > 0.25 { limitations.append(.manyDefaults) }
        if estimates.contains(where: { $0.finding == .uncertain }) || comparison?.estimate.finding == .uncertain {
            limitations.append(.indeterminateInterval)
        }
        return result(.low, limitations, estimates: estimates, interactionEstimate: comparison?.estimate, lagDays: maximumLag)
    }

    static func inputColumns(_ observations: [AnalysisObservation], inputs: [AnalysisModeledInput]) -> [[Double]]? {
        let columns = inputs.enumerated().map { index, input in
            if let threshold = input.kind?.ratingThreshold {
                return observations.compactMap {
                    RatingAnalysis.indicator($0.inputs[index].trackingValue, threshold: threshold)
                }
            }
            return observations.map { $0.inputs[index].value }
        }
        return columns.allSatisfy { $0.count == observations.count } ? columns : nil
    }

    static func inputLimitations(
        _ observations: [AnalysisObservation], inputs: [AnalysisModeledInput], columns: [[Double]]
    ) -> [AnalysisEvidence.Reason] {
        var defaultOnly: Set<AnalysisSeriesID> = []
        var lowVariation: Set<AnalysisSeriesID> = []
        var sparseRatings: Set<AnalysisSeriesID> = []
        for (index, input) in inputs.enumerated() {
            let column = columns[index]
            let observed = zip(observations, column).compactMap { $0.inputs[index].origin == .observation ? $1 : nil }
            if !observations.contains(where: { $0.inputs[index].hasObservedDay }) {
                defaultOnly.insert(input.series)
            } else if input.kind?.ratingThreshold != nil {
                if !RatingAnalysis.hasSupport(observed) { sparseRatings.insert(input.series) }
            } else if !hasVariation(column, input: input) || !hasVariation(observed, input: input) {
                lowVariation.insert(input.series)
            }
        }
        var limitations: [AnalysisEvidence.Reason] = []
        if !defaultOnly.isEmpty { limitations.append(.defaultOnlyInputs(defaultOnly)) }
        if !lowVariation.isEmpty { limitations.append(.lowVariationInputs(lowVariation)) }
        if !sparseRatings.isEmpty { limitations.append(.sparseObservedRatingInputs(sparseRatings)) }
        return limitations
    }

    private static func hasVariation(_ values: [Double], input: AnalysisModeledInput) -> Bool {
        if input.kind == .tracked(.yesNo) { return BinaryEvent.hasSupport(values) }
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
