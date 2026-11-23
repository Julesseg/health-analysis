public struct AnalysisCapabilities: Sendable {
    public enum Limitation: CaseIterable, Hashable, Sendable {
        case category, clock, yesNo, rating, count

        fileprivate var windowFailure: AnalysisRunFailure {
            switch self {
            case .category: .categoryWindowUnavailable
            case .clock: .clockWindowUnavailable
            case .yesNo: .binaryWindowUnavailable
            case .rating: .ratingWindowUnavailable
            case .count: .countWindowUnavailable
            }
        }

        fileprivate var interactionFailure: AnalysisRunFailure {
            switch self {
            case .category: .categoryInteractionUnavailable
            case .clock: .clockInteractionUnavailable
            case .yesNo: .binaryInteractionUnavailable
            case .rating: .ratingInteractionUnavailable
            case .count: .countInteractionUnavailable
            }
        }
    }

    public let limitations: Set<Limitation>
    public var allowsLongerWindows: Bool { limitations.isEmpty }
    public var allowsInteractions: Bool { limitations.isEmpty }
    public var supportsCombination: Bool { !(limitations.contains(.category) && limitations.contains(.yesNo)) }

    public init(variables: [AnalysisVariable]) {
        limitations = Set(variables.compactMap { variable in
            switch variable.kind {
            case .tracked(.category): .category
            case .tracked(.timeOfDay): .clock
            case .tracked(.yesNo): .yesNo
            case .tracked(.rating) where variable.kind.ratingThreshold != nil: .rating
            case .tracked(.count): .count
            default: nil
            }
        })
    }

    func validate(_ configuration: AnalysisConfiguration) throws(AnalysisRunFailure) {
        guard supportsCombination else { throw .categoryModelCombinationUnavailable }
        for limitation in Limitation.allCases where limitations.contains(limitation) {
            if configuration.behaviorWindow != .precedingDay { throw limitation.windowFailure }
            if configuration.interaction != nil { throw limitation.interactionFailure }
        }
    }
}
