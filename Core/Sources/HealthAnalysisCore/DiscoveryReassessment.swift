import Foundation

public struct DiscoveryReassessment: Codable, Sendable {
    public enum Support: String, Codable, Sendable {
        case noLaterObservations
        case insufficient
        case sameDirection
        case oppositeDirection
        case nearZero
        case uncertain
    }

    public let result: AnalysisResult
    public let support: Support

    public var latestEligibleOutputDate: Date? {
        [result.coverage.lastDate, result.coverage.outputDatesWithoutCompleteInput.last].compactMap { $0 }.max()
    }

    init(result: AnalysisResult, original: AnalysisResult, contrast: DiscoverySelection.Contrast) {
        self.result = result
        let initial = original.discoveryEstimate(for: contrast)
        let later = result.discoveryEstimate(for: contrast)
        if result.coverage.outputDayCount == 0 {
            support = .noLaterObservations
        } else if let initial, let later {
            if later.finding == .nearZero {
                support = .nearZero
            } else if later.interval.contains(0) {
                support = .uncertain
            } else {
                support = initial.difference.sign == later.difference.sign ? .sameDirection : .oppositeDirection
            }
        } else {
            support = .insufficient
        }
    }
}

extension AnalysisResult {
    fileprivate func discoveryEstimate(
        for contrast: DiscoverySelection.Contrast
    ) -> (difference: Double, interval: ClosedRange<Double>, finding: AnalysisEstimate.Finding)? {
        switch contrast {
        case .input(let id):
            guard let estimate = estimates.first(where: { $0.input == id }) else { return nil }
            return (estimate.difference, estimate.interval, estimate.finding)
        case .interaction(let pair):
            guard configuration.interaction == pair, let interaction else { return nil }
            return (interaction.difference, interaction.interval, interaction.finding)
        }
    }
}
