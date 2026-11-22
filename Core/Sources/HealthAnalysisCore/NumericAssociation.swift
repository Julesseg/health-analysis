import Foundation

public struct AnalysisEstimate: Codable, Sendable {
    public struct Reference: Codable, Sendable {
        public let input: AnalysisSeriesID
        public let value: Double
    }

    public enum Finding: Codable, Sendable {
        case higher
        case lower
        case nearZero
        case uncertain
    }

    public let input: AnalysisSeriesID
    public let inputIncrement: Double
    public let difference: Double
    public let interval: ClosedRange<Double>
    public let finding: Finding
    public let reference: Reference?

    init(
        input: AnalysisSeriesID, inputIncrement: Double, difference: Double, interval: ClosedRange<Double>,
        finding: Finding, reference: Reference? = nil
    ) {
        self.input = input
        self.inputIncrement = inputIncrement
        self.difference = difference
        self.interval = interval
        self.finding = finding
        self.reference = reference
    }
}

public struct AnalysisEvidence: Codable, Sendable {
    public enum Grade: Codable, Sendable {
        case insufficient
        case low
        case moderate
    }

    public enum Reason: Codable, Hashable, Sendable {
        case inadequateCoverage
        case inadequateJointCoverage(minimumDays: Int)
        case limitedNonOverlappingWindows
        case overlappingBehaviorWindows
        case noObservedInputs
        case limitedInputVariation
        case uncertaintyUnavailable
        case limitedHistory
        case sparseCoverage
        case manyDefaults
        case wideInterval
        case indeterminateInterval
        case adequateCoverageAndPrecision
        case adjustedModelLimitations
        case collinearInputs(Set<AnalysisSeriesID>)
        case defaultOnlyInputs(Set<AnalysisSeriesID>)
        case lowVariationInputs(Set<AnalysisSeriesID>)
        case poorlyRepresentedInteraction(AnalysisInteractionSupport)
    }

    public let grade: Grade
    public let reasons: [Reason]
    public let defaultDayCount: Int
    public let dependenceLagDays: Int?
}

enum NumericAssociation {
    static func assess(
        _ observations: [AnalysisObservation], coverage: AnalysisCoverage, calendar: Calendar,
        behaviorWindow: AnalysisBehaviorWindow = .precedingDay, practicalDifference: Double = 1
    ) -> (estimate: AnalysisEstimate?, evidence: AnalysisEvidence) {
        let count = observations.count
        let defaultDays = observations.reduce(into: 0) { days, observation in
            if observation.inputs.contains(where: { $0.origin != .observation }) { days += 1 }
        }

        func insufficient(_ reason: AnalysisEvidence.Reason) -> (AnalysisEstimate?, AnalysisEvidence) {
            (nil, AnalysisEvidence(
                grade: .insufficient, reasons: [reason], defaultDayCount: defaultDays, dependenceLagDays: nil
            ))
        }

        guard count >= 42 else { return insufficient(.inadequateCoverage) }
        guard coverage.nonOverlappingWindowCount >= 6 else { return insufficient(.limitedNonOverlappingWindows) }
        let hasObservedInput = observations.contains { observation in
            observation.inputs.contains(where: \.hasObservedDay)
        }
        guard hasObservedInput else { return insufficient(.noObservedInputs) }
        let dayNumbers = observations.compactMap { calendar.ordinality(of: .day, in: .era, for: $0.outputDate) }
        guard dayNumbers.count == count else { return insufficient(.uncertaintyUnavailable) }

        let amounts = observations.map { $0.inputs[0].value }
        let sortedAmounts = amounts.sorted()
        guard sortedAmounts[3 * count / 4] - sortedAmounts[count / 4] >= 20 else {
            return insufficient(.limitedInputVariation)
        }

        let increment = 100.0
        guard let input = observations.first?.inputs.first?.series,
              let fit = fit(
                amounts.map { $0 / increment }, observations.map(\.outputValue),
                dayNumbers: dayNumbers, windowDays: behaviorWindow.dayCount
              ) else { return insufficient(.uncertaintyUnavailable) }

        let interval = (fit.slope - fit.halfWidth)...(fit.slope + fit.halfWidth)
        let reference = practicalDifference
        let finding: AnalysisEstimate.Finding
        if interval.lowerBound >= -reference && interval.upperBound <= reference {
            finding = .nearZero
        } else if interval.lowerBound > 0 {
            finding = .higher
        } else if interval.upperBound < 0 {
            finding = .lower
        } else {
            finding = .uncertain
        }

        var reasons: [AnalysisEvidence.Reason] = []
        if coverage.nonOverlappingWindowCount < count { reasons.append(.overlappingBehaviorWindows) }
        if count < 90 { reasons.append(.limitedHistory) }
        if Double(count) / Double(count + coverage.missingDays) < 0.75 { reasons.append(.sparseCoverage) }
        if Double(defaultDays) / Double(count) > 0.25 { reasons.append(.manyDefaults) }
        if fit.halfWidth > reference {
            reasons.append(.wideInterval)
        } else if finding == .uncertain {
            reasons.append(.indeterminateInterval)
        }
        let evidence = AnalysisEvidence(
            grade: reasons.isEmpty ? .moderate : .low,
            reasons: reasons.isEmpty ? [.adequateCoverageAndPrecision] : reasons,
            defaultDayCount: defaultDays,
            dependenceLagDays: fit.lagDays
        )
        return (AnalysisEstimate(
            input: input, inputIncrement: increment, difference: fit.slope, interval: interval, finding: finding
        ), evidence)
    }

    private static func fit(
        _ inputs: [Double], _ outputs: [Double], dayNumbers: [Int], windowDays: Int
    ) -> (slope: Double, halfWidth: Double, lagDays: Int)? {
        let count = Double(inputs.count)
        let meanInput = inputs.reduce(0, +) / count
        let meanOutput = outputs.reduce(0, +) / count
        let centeredInput = inputs.map { $0 - meanInput }
        let centeredOutput = outputs.map { $0 - meanOutput }
        let inputScale = centeredInput.map(abs).max() ?? 0
        guard inputScale > 0, inputScale.isFinite else { return nil }

        let design = centeredInput.map { $0 / inputScale }
        let sumSquares = design.reduce(0) { $0 + $1 * $1 }
        let scaledSlope = zip(design, centeredOutput).reduce(0) { $0 + $1.0 * $1.1 } / sumSquares
        let residuals = zip(design, centeredOutput).map { $1 - $0 * scaledSlope }
        let scores = zip(design, residuals).map(*)
        let slope = scaledSlope / inputScale
        let uncertainty = TemporalAssociationUncertainty.assess(
            scores: scores, residuals: residuals, dayNumbers: dayNumbers,
            windowDays: windowDays, parameterCount: 2
        )
        let halfWidth = uncertainty.scoreHalfWidth / (sumSquares * inputScale)

        guard let maxResidual = residuals.map(abs).max(),
              maxResidual > 64 * Double.ulpOfOne * abs(meanOutput),
              halfWidth > 0, (abs(slope) + halfWidth).isFinite else { return nil }
        return (slope, halfWidth, uncertainty.lagDays)
    }
}
