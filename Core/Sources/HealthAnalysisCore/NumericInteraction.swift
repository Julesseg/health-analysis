import Foundation

public struct AnalysisInteraction: Codable, Hashable, Sendable {
    public let focal: AnalysisSeriesID
    public let moderator: AnalysisSeriesID

    public init(focal: AnalysisSeriesID, moderator: AnalysisSeriesID) {
        self.focal = focal
        self.moderator = moderator
    }

    func isValid(for inputs: [AnalysisSeriesID]) -> Bool {
        focal != moderator && inputs.contains(focal) && inputs.contains(moderator)
    }
}

public struct AnalysisInteractionEstimate: Codable, Sendable {
    public struct Condition: Codable, Sendable {
        public let moderatorValue: Double
        public let difference: Double
        public let interval: ClosedRange<Double>
    }

    public let focalValues: ClosedRange<Double>
    public let lowerCondition: Condition
    public let higherCondition: Condition
    public let difference: Double
    public let interval: ClosedRange<Double>
    public let finding: AnalysisEstimate.Finding
    public let support: AnalysisInteractionSupport
}

public struct AnalysisInteractionSupport: Codable, Hashable, Sendable {
    public enum Combination: String, Codable, CaseIterable, Hashable, Sendable {
        case lowerFocalLowerModerator
        case higherFocalLowerModerator
        case lowerFocalHigherModerator
        case higherFocalHigherModerator
    }

    public let explicitlyObservedPairDays: Int
    public let minimumDaysPerCombination: Int
    public let explicitDaysByCombination: [Combination: Int]
}

struct NumericInteractionDesign {
    enum Preparation {
        case supported(NumericInteractionDesign)
        case insufficient(AnalysisInteractionSupport)
    }

    private let inputs: [AnalysisModeledInput]
    private let focalIndex: Int
    private let moderatorIndex: Int
    private let focal: ObservedLevels
    private let moderator: ObservedLevels
    private let support: AnalysisInteractionSupport
    let productColumn: [Double]

    static func prepare(
        inputs: [AnalysisModeledInput], focal focalIndex: Int, moderator moderatorIndex: Int,
        rows: [AnalysisObservation]
    ) -> Preparation {
        let observedPairs = rows.compactMap { row -> (Double, Double)? in
            let focal = row.inputs[focalIndex]
            let moderator = row.inputs[moderatorIndex]
            guard focal.origin == .observation, moderator.origin == .observation else { return nil }
            return (focal.value, moderator.value)
        }
        let minimumDays = max(5, Int(ceil(Double(observedPairs.count) * 0.025)))
        guard let focal = ObservedLevels(observedPairs.map(\.0), input: inputs[focalIndex]),
              let moderator = ObservedLevels(observedPairs.map(\.1), input: inputs[moderatorIndex]) else {
            return .insufficient(.init(
                explicitlyObservedPairDays: observedPairs.count, minimumDaysPerCombination: minimumDays,
                explicitDaysByCombination: [:]
            ))
        }
        var counts: [AnalysisInteractionSupport.Combination: Int] = [
            .lowerFocalLowerModerator: 0, .higherFocalLowerModerator: 0,
            .lowerFocalHigherModerator: 0, .higherFocalHigherModerator: 0
        ]
        for (focalValue, moderatorValue) in observedPairs {
            switch (focal.isHigher(focalValue), moderator.isHigher(moderatorValue)) {
            case (false?, false?): counts[.lowerFocalLowerModerator, default: 0] += 1
            case (true?, false?): counts[.higherFocalLowerModerator, default: 0] += 1
            case (false?, true?): counts[.lowerFocalHigherModerator, default: 0] += 1
            case (true?, true?): counts[.higherFocalHigherModerator, default: 0] += 1
            default: break
            }
        }
        let support = AnalysisInteractionSupport(
            explicitlyObservedPairDays: observedPairs.count, minimumDaysPerCombination: minimumDays,
            explicitDaysByCombination: counts
        )
        guard counts.values.allSatisfy({ $0 >= minimumDays }) else { return .insufficient(support) }
        let productColumn = rows.map {
            ($0.inputs[focalIndex].value - focal.median) * ($0.inputs[moderatorIndex].value - moderator.median)
        }
        return .supported(.init(
            inputs: inputs, focalIndex: focalIndex, moderatorIndex: moderatorIndex,
            focal: focal, moderator: moderator, support: support, productColumn: productColumn
        ))
    }

    func reference(for index: Int) -> AnalysisEstimate.Reference? {
        switch index {
        case focalIndex: .init(input: inputs[moderatorIndex].series, value: moderator.median)
        case moderatorIndex: .init(input: inputs[focalIndex].series, value: focal.median)
        default: nil
        }
    }

    func estimate(
        using fit: LinearAssociationFit, practicalDifference: Double
    ) -> (estimate: AnalysisInteractionEstimate, lagDays: Int)? {
        let focalChange = focal.upper - focal.lower
        func condition(at value: Double) -> (condition: AnalysisInteractionEstimate.Condition, lagDays: Int)? {
            var contrast = Array(repeating: 0.0, count: inputs.count + 1)
            contrast[focalIndex] = focalChange
            contrast[inputs.count] = focalChange * (value - moderator.median)
            guard let estimate = fit.estimate(contrast: contrast) else { return nil }
            let condition = AnalysisInteractionEstimate.Condition(
                moderatorValue: value, difference: estimate.difference,
                interval: (estimate.difference - estimate.halfWidth)...(estimate.difference + estimate.halfWidth)
            )
            return (condition, estimate.lagDays)
        }
        var changeContrast = Array(repeating: 0.0, count: inputs.count + 1)
        changeContrast[inputs.count] = focalChange * (moderator.upper - moderator.lower)
        guard let lower = condition(at: moderator.lower), let higher = condition(at: moderator.upper),
              let change = fit.estimate(contrast: changeContrast) else { return nil }
        let interval = (change.difference - change.halfWidth)...(change.difference + change.halfWidth)
        let estimate = AnalysisInteractionEstimate(
            focalValues: focal.lower...focal.upper, lowerCondition: lower.condition, higherCondition: higher.condition,
            difference: change.difference, interval: interval,
            finding: NumericAnalysis.finding(interval, nearZero: practicalDifference),
            support: support
        )
        return (estimate, max(lower.lagDays, higher.lagDays, change.lagDays))
    }
}

private struct ObservedLevels {
    let lower: Double
    let median: Double
    let upper: Double

    init?(_ values: [Double], input: AnalysisModeledInput) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        lower = sorted[count / 4]
        upper = sorted[3 * count / 4]
        median = sorted[(count - 1) / 2] / 2 + sorted[count / 2] / 2
        guard input.hasVariation(from: lower, to: upper) else { return nil }
    }

    func isHigher(_ value: Double) -> Bool? {
        if value <= lower { return false }
        if value >= upper { return true }
        return nil
    }
}
