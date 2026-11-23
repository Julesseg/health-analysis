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

    public struct Confirmation: Codable, Sendable {
        public let firstDay: Date
        public let endBefore: Date
        public let blockCount: Int
        public let pValue: Double
        public let threshold: Double
    }

    public let result: AnalysisResult
    public let confirmation: Confirmation?
    public let support: Support

    public var latestEligibleOutputDate: Date? {
        [result.coverage.lastDate, result.coverage.outputDatesWithoutCompleteInput.last].compactMap { $0 }.max()
    }

    init(
        result: AnalysisResult, original: AnalysisResult, selection: DiscoverySelection,
        confirmationFit: AnalysisResult?, period: ConfirmationPeriod?
    ) {
        let initial = original.discoveryEstimate(for: selection.contrast)
        let later = result.discoveryEstimate(for: selection.contrast)
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

        var graded = result
        if support == .sameDirection, let initial, let later, initial.interval.overlaps(later.interval),
           let period, let confirmationFit,
           let evidence = period.assess(confirmationFit, initial: initial, selection: selection) {
            confirmation = evidence
            graded.evidence = .init(
                grade: .high, reasons: result.evidence.reasons + [.confirmedLaterAssociation],
                defaultDayCount: result.evidence.defaultDayCount, dependenceLagDays: result.evidence.dependenceLagDays
            )
        } else {
            confirmation = nil
        }
        self.result = graded
    }

    struct ConfirmationPeriod: Sendable {
        let firstDay: Date
        let endBefore: Date
        let calendar: Calendar

        var asOf: Date { Date(timeIntervalSinceReferenceDate: endBefore.timeIntervalSinceReferenceDate.nextDown) }

        init?(configuration: AnalysisConfiguration, selection: DiscoverySelection, asOf: Date) {
            guard selection.methodVersion == 1, selection.familySize > 0,
                  selection.adjustedPValue <= DiscoverySearch.familyThreshold,
                  case .input(let input) = selection.contrast, case .manualQuantity = input,
                  configuration.inputs == [input], configuration.adjustmentInputs.isEmpty,
                  configuration.interaction == nil, configuration.behaviorWindow == .precedingDay,
                  configuration.history == .last365Days, configuration.output.usesCaffeineModel
            else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = configuration.timeZone
            guard let first = calendar.dateInterval(of: .day, for: selection.cutoff)?.end,
                  let end = calendar.date(byAdding: .day, value: DiscoverySearch.historyDays, to: first),
                  asOf >= end else { return nil }
            self.calendar = calendar
            firstDay = first
            endBefore = end
        }

        func assess(
            _ fit: AnalysisResult, initial: (difference: Double, interval: ClosedRange<Double>, finding: AnalysisEstimate.Finding),
            selection: DiscoverySelection
        ) -> Confirmation? {
            let estimate = fit.discoveryEstimate(for: selection.contrast)
            let threshold = min(0.01, DiscoverySearch.familyThreshold / Double(selection.familySize))
            guard fit.evidence.grade == .moderate || fit.evidence.reasons == [.adjustedModelLimitations],
                  fit.evidence.defaultDayCount == 0,
                  let estimate, estimate.difference.sign == initial.difference.sign,
                  !estimate.interval.contains(0), estimate.interval.overlaps(initial.interval),
                  let blocks = DiscoveryBlockEvidence.assess(fit, startOfHistory: firstDay, calendar: calendar),
                  blocks.directionsAgree, blocks.mean.sign == initial.difference.sign, blocks.pValue <= threshold
            else { return nil }
            return .init(
                firstDay: firstDay, endBefore: endBefore, blockCount: DiscoveryBlockEvidence.blockCount,
                pValue: blocks.pValue, threshold: threshold
            )
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
