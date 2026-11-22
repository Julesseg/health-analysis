import Foundation

public struct AnalysisEstimate: Codable, Sendable {
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
}

public struct AnalysisEvidence: Codable, Sendable {
    public enum Grade: Codable, Sendable {
        case insufficient
        case low
        case moderate
    }

    public enum Reason: Codable, Sendable {
        case inadequateCoverage
        case noObservedInputs
        case limitedInputVariation
        case uncertaintyUnavailable
        case limitedHistory
        case sparseCoverage
        case manyDefaults
        case wideInterval
        case indeterminateInterval
        case adequateCoverageAndPrecision
    }

    public let grade: Grade
    public let reasons: [Reason]
    public let defaultDayCount: Int
    public let dependenceLagDays: Int?
}

enum NumericAssociation {
    static func assess(
        _ observations: [AnalysisObservation], coverage: AnalysisCoverage, calendar: Calendar
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
        guard defaultDays < count else { return insufficient(.noObservedInputs) }
        let dayNumbers = observations.compactMap { calendar.ordinality(of: .day, in: .era, for: $0.outputDate) }
        guard dayNumbers.count == count else { return insufficient(.uncertaintyUnavailable) }

        let amounts = observations.map { $0.inputs[0].value }
        let sortedAmounts = amounts.sorted()
        guard sortedAmounts[3 * count / 4] - sortedAmounts[count / 4] >= 20 else {
            return insufficient(.limitedInputVariation)
        }

        let lagDays = max(7, Int(ceil(2 * pow(Double(count), 1.0 / 3.0))))
        let increment = 100.0
        guard let input = observations.first?.inputs.first?.series,
              let fit = fit(
                amounts.map { $0 / increment }, observations.map(\.outputValue),
                dayNumbers: dayNumbers, lagDays: lagDays
              ) else { return insufficient(.uncertaintyUnavailable) }

        let interval = (fit.slope - fit.halfWidth)...(fit.slope + fit.halfWidth)
        let reference = 1.0
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
            dependenceLagDays: lagDays
        )
        return (AnalysisEstimate(
            input: input, inputIncrement: increment, difference: fit.slope, interval: interval, finding: finding
        ), evidence)
    }

    private static func fit(
        _ inputs: [Double], _ outputs: [Double], dayNumbers: [Int], lagDays: Int
    ) -> (slope: Double, halfWidth: Double)? {
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
        let scoreVariance = bartlettSum(scores, dayNumbers: dayNumbers, lagDays: lagDays)
        let divisor = sumSquares * inputScale
        let variance = (count / (count - 2)) * scoreVariance / (divisor * divisor)
        let slope = scaledSlope / inputScale
        let bandwidthFraction = Double(lagDays + 1) / count
        let criticalValue = 1.96 + bandwidthFraction
            * (2.9694 + bandwidthFraction * (0.4160 - 0.5324 * bandwidthFraction))
        let halfWidth = criticalValue * sqrt(variance)

        guard let maxResidual = residuals.map(abs).max(),
              maxResidual > 64 * Double.ulpOfOne * abs(meanOutput),
              halfWidth > 0, (abs(slope) + halfWidth).isFinite else { return nil }
        return (slope, halfWidth)
    }

    private static func bartlettSum(_ scores: [Double], dayNumbers: [Int], lagDays: Int) -> Double {
        var sum = scores.reduce(0) { $0 + $1 * $1 }
        for index in scores.indices.dropFirst() {
            for prior in (0..<index).reversed() {
                let lag = dayNumbers[index] - dayNumbers[prior]
                if lag > lagDays { break }
                let weight = 1 - Double(lag) / Double(lagDays + 1)
                sum += 2 * weight * scores[index] * scores[prior]
            }
        }
        return sum
    }
}
