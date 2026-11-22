import Foundation

public struct AnalysisCategoryContrast: Codable, Hashable, Sendable {
    public var reference: TrackingCategory.ID
    public var comparison: TrackingCategory.ID

    public init(reference: TrackingCategory.ID, comparison: TrackingCategory.ID) {
        self.reference = reference
        self.comparison = comparison
    }
}

public struct AnalysisCategoryConfiguration: Codable, Hashable, Sendable {
    public var inputContrasts: [AnalysisSeriesID: AnalysisCategoryContrast]
    public var outputEvent: TrackingCategory.ID?

    public init(
        inputContrasts: [AnalysisSeriesID: AnalysisCategoryContrast] = [:], outputEvent: TrackingCategory.ID? = nil
    ) {
        self.inputContrasts = inputContrasts
        self.outputEvent = outputEvent
    }
}

public struct AnalysisCategoryEvidence: Codable, Sendable {
    public struct Level: Codable, Identifiable, Sendable {
        public var id: TrackingCategory.ID { category.id }
        public let category: TrackingCategory
        public let pairedDayCount: Int
        public let recordedDayCount: Int
        public let eventSupport: EventSupport?
    }

    public struct EventSupport: Codable, Sendable {
        public let eventDayCount: Int
        public let otherDayCount: Int
    }

    public let inputLevels: [AnalysisSeriesID: [Level]]
    public let outputLevels: [Level]
    public let excludedOutputDates: [Date]
}

struct CategoryAnalysis {
    static let minimumRecordedDaysPerLevel = 6

    enum Transform {
        case contrast(AnalysisCategoryContrast)
        case event(TrackingCategory.ID)

        func encode(_ id: TrackingCategory.ID) -> Double? {
            switch self {
            case .contrast(let contrast):
                if id == contrast.reference { return 0 }
                if id == contrast.comparison { return 1 }
                return nil
            case .event(let event):
                return id == event ? 1 : 0
            }
        }
    }

    let inputContrasts: [AnalysisSeriesID: AnalysisCategoryContrast]
    let outputEvent: TrackingCategory.ID?

    init(
        configuration: AnalysisConfiguration, inputs: [AnalysisVariable], output: AnalysisVariable?
    ) throws(AnalysisRunFailure) {
        inputContrasts = configuration.categories?.inputContrasts ?? [:]
        outputEvent = configuration.categories?.outputEvent
        let categoryInputs = inputs.filter { !$0.categories.isEmpty }
        let outputOptions = output?.categories ?? []
        guard Set(categoryInputs.map(\.id)) == Set(inputContrasts.keys),
              categoryInputs.allSatisfy({ input in
                  guard let contrast = inputContrasts[input.id], contrast.reference != contrast.comparison else {
                      return false
                  }
                  return input.categories.contains { $0.id == contrast.reference }
                      && input.categories.contains { $0.id == contrast.comparison }
              }),
              outputOptions.isEmpty ? outputEvent == nil : outputOptions.contains(where: { $0.id == outputEvent })
        else { throw .categorySelectionUnavailable }
        if !categoryInputs.isEmpty || !outputOptions.isEmpty {
            guard configuration.behaviorWindow == .precedingDay else { throw .categoryWindowUnavailable }
            guard configuration.interaction == nil else { throw .categoryInteractionUnavailable }
        }
    }

    var isUsed: Bool { !inputContrasts.isEmpty || outputEvent != nil }

    func summarize(
        _ dataset: TemporalAnalysisDataset, inputs: [AnalysisVariable], output: AnalysisVariable?
    ) -> AnalysisCategoryEvidence? {
        guard isUsed else { return nil }
        let rows = dataset.observations
        var inputLevels: [AnalysisSeriesID: [AnalysisCategoryEvidence.Level]] = [:]
        for (index, input) in inputs.enumerated() {
            if let contrast = inputContrasts[input.id] {
                let options = [contrast.reference, contrast.comparison].compactMap { id in
                    input.categories.first { $0.id == id }
                }
                inputLevels[input.id] = levels(options, samples: rows.map {
                    let event: Bool? = outputEvent == nil || $0.outputOrigin != .observation ? nil : $0.outputValue == 1
                    return ($0.inputs[index].trackingValue, $0.inputs[index].origin, event)
                })
            }
        }
        return AnalysisCategoryEvidence(
            inputLevels: inputLevels,
            outputLevels: levels(output?.categories ?? [], samples: rows.map {
                ($0.outputTrackingValue, $0.outputOrigin, nil)
            }),
            excludedOutputDates: dataset.inspection.unpairedOutputs.compactMap {
                $0.excludedCategoryInputs == nil ? nil : $0.date
            }
        )
    }

    private func levels(
        _ categories: [TrackingCategory], samples: [(ManualTrackingValue?, ManualValueOrigin?, Bool?)]
    ) -> [AnalysisCategoryEvidence.Level] {
        var paired: [TrackingCategory.ID: Int] = [:]
        var recorded: [TrackingCategory.ID: Int] = [:]
        var eventDays: [TrackingCategory.ID: Int] = [:]
        var otherDays: [TrackingCategory.ID: Int] = [:]
        for (value, origin, observedEvent) in samples {
            guard case .category(let id)? = value else { continue }
            paired[id, default: 0] += 1
            if origin == .observation {
                recorded[id, default: 0] += 1
                if observedEvent == true { eventDays[id, default: 0] += 1 }
                if observedEvent == false { otherDays[id, default: 0] += 1 }
            }
        }
        let hasEventSamples = !eventDays.isEmpty || !otherDays.isEmpty
        return categories.map {
            let eventSupport: AnalysisCategoryEvidence.EventSupport? = hasEventSamples
                ? .init(eventDayCount: eventDays[$0.id, default: 0], otherDayCount: otherDays[$0.id, default: 0]) : nil
            return .init(
                category: $0, pairedDayCount: paired[$0.id, default: 0],
                recordedDayCount: recorded[$0.id, default: 0], eventSupport: eventSupport
            )
        }
    }

    static func assessInputContrasts(
        _ evidence: AnalysisCategoryEvidence, observations: [AnalysisObservation], assessment: () -> NumericAnalysis,
        model: AnalysisModel
    ) -> NumericAnalysis {
        let sparseInputs = Set(evidence.inputLevels.filter { _, levels in
            levels.contains { $0.recordedDayCount < minimumRecordedDaysPerLevel }
        }.keys)
        if !sparseInputs.isEmpty {
            return NumericAnalysis(model: model, estimates: [], interaction: nil, evidence: AnalysisEvidence(
                grade: .insufficient, reasons: [.sparseCategoryInputs(sparseInputs)],
                defaultDayCount: observations.count { row in
                    row.outputOrigin.map { $0 != .observation } == true || row.inputs.contains { $0.origin != .observation }
                },
                dependenceLagDays: nil
            ))
        }

        let fit = assessment()
        guard fit.evidence.grade != .insufficient else { return fit }
        guard model != .categoryEventLogisticV1 else { return fit }
        let reasons = fit.evidence.reasons.filter { $0 != .adequateCoverageAndPrecision }
        return NumericAnalysis(model: fit.model, estimates: fit.estimates, interaction: nil, evidence: AnalysisEvidence(
            grade: .low, reasons: reasons + [.categoryModelLimitations],
            defaultDayCount: fit.evidence.defaultDayCount, dependenceLagDays: fit.evidence.dependenceLagDays
        ))
    }
}
