import Foundation

public enum AnalysisSeriesID: Codable, Hashable, Sendable {
    case manualQuantity(UUID)
    case health(metric: HealthMeasurement.Metric, sourceBundleIdentifier: String? = nil)
}

public enum AnalysisBehaviorWindow: String, CaseIterable, Codable, Hashable, Sendable {
    case precedingDay
    case precedingWeek
    case precedingMonth

    public var dayCount: Int {
        switch self {
        case .precedingDay: 1
        case .precedingWeek: 7
        case .precedingMonth: 30
        }
    }
}

public enum AnalysisPeriod: String, CaseIterable, Codable, Hashable, Sendable {
    case fullHistory
    case last90Days
    case last365Days

    var dayCount: Int? {
        switch self {
        case .fullHistory: nil
        case .last90Days: 90
        case .last365Days: 365
        }
    }
}

public struct AnalysisConfiguration: Codable, Hashable, Sendable {
    public var output: AnalysisSeriesID
    public var inputs: [AnalysisSeriesID]
    public var adjustmentInputs: [AnalysisSeriesID]
    public var interaction: AnalysisInteraction?
    public var behaviorWindow: AnalysisBehaviorWindow
    public var history: AnalysisPeriod
    public var timeZone: TimeZone

    public init(
        output: AnalysisSeriesID,
        inputs: [AnalysisSeriesID],
        adjustmentInputs: [AnalysisSeriesID] = [],
        interaction: AnalysisInteraction? = nil,
        behaviorWindow: AnalysisBehaviorWindow = .precedingDay,
        history: AnalysisPeriod = .fullHistory,
        timeZone: TimeZone = .current
    ) {
        self.output = output
        self.inputs = inputs
        self.adjustmentInputs = adjustmentInputs
        self.interaction = interaction
        self.behaviorWindow = behaviorWindow
        self.history = history
        self.timeZone = timeZone
    }
}

public struct AnalysisObservation: Identifiable, Codable, Sendable {
    public struct Input: Codable, Sendable {
        public struct Day: Codable, Sendable {
            public let date: Date
            public let value: Double
            public let origin: ManualValueOrigin
        }

        public let series: AnalysisSeriesID
        public let date: Date
        public let value: Double
        public let origin: ManualValueOrigin
        public let days: [Day]

        var hasObservedDay: Bool { origin == .observation || days.contains { $0.origin == .observation } }

        init(series: AnalysisSeriesID, date: Date, value: Double, origin: ManualValueOrigin, days: [Day] = []) {
            self.series = series
            self.date = date
            self.value = value
            self.origin = origin
            self.days = days
        }
    }

    public var id: Date { outputDate }
    public let outputDate: Date
    public let outputAnchor: Date
    public let outputValue: Double
    public let inputs: [Input]
}

public struct AnalysisCoverage: Codable, Sendable {
    public struct Gap: Identifiable, Codable, Sendable {
        public var id: Date { firstDate }
        public let firstDate: Date
        public let lastDate: Date
        public let dayCount: Int
    }

    public let usableDates: [Date]
    public let gaps: [Gap]
    public let outputDaysWithoutCompleteInput: Int
    public let outputDatesWithoutCompleteInput: [Date]
    public let distinctBehaviorDayCount: Int
    public let nonOverlappingWindowCount: Int

    public var firstDate: Date? { usableDates.first }
    public var lastDate: Date? { usableDates.last }
    public var missingDays: Int { gaps.reduce(0) { $0 + $1.dayCount } }
    public var outputDayCount: Int { usableDates.count + outputDaysWithoutCompleteInput }

    init(observations: [AnalysisObservation], outputDates: [Date], calendar: Calendar) {
        usableDates = observations.map(\.outputDate)
        let usable = Set(usableDates)
        outputDatesWithoutCompleteInput = outputDates.filter { !usable.contains($0) }
        outputDaysWithoutCompleteInput = outputDatesWithoutCompleteInput.count
        var distinctDays: Set<Date> = []
        let windows = observations.compactMap { observation -> ClosedRange<Date>? in
            guard let input = observation.inputs.first else { return nil }
            distinctDays.formUnion(input.days.map(\.date))
            return input.date...(input.days.last?.date ?? input.date)
        }.sorted { $0.upperBound < $1.upperBound }
        distinctBehaviorDayCount = distinctDays.count
        var lastEnd = Date.distantPast
        nonOverlappingWindowCount = windows.reduce(into: 0) { count, window in
            if window.lowerBound > lastEnd {
                count += 1
                lastEnd = window.upperBound
            }
        }
        gaps = zip(usableDates, usableDates.dropFirst()).compactMap { earlier, later in
            guard let earlierDay = calendar.ordinality(of: .day, in: .era, for: earlier),
                  let laterDay = calendar.ordinality(of: .day, in: .era, for: later),
                  laterDay - earlierDay > 1,
                  let first = calendar.dateInterval(of: .day, for: earlier)?.end,
                  let last = calendar.dateInterval(of: .day, for: later.addingTimeInterval(-1))?.start else {
                return nil
            }
            return Gap(firstDate: first, lastDate: last, dayCount: laterDay - earlierDay - 1)
        }
    }
}

public struct AnalysisResult: Codable, Sendable {
    public let configuration: AnalysisConfiguration
    public let outputSource: HealthMeasurement.Source?
    public let healthHistoryReadAt: Date?
    public let lastHealthReadFailure: HealthMeasurementReadFailure?
    public let observations: [AnalysisObservation]
    public let coverage: AnalysisCoverage
    public let model: AnalysisModel
    public let modeledInputs: [AnalysisModeledInput]
    public let estimates: [AnalysisEstimate]
    public let interaction: AnalysisInteractionEstimate?
    public let evidence: AnalysisEvidence
}

public enum AnalysisRunFailure: Error, Equatable {
    case unsupportedConfiguration
    case inputUnavailable
    case manualLogUnavailable
    case chooseOutputSource
    case healthHistoryUnavailable(HealthMeasurementReadFailure)
    case healthHistoryLoading
}

extension HealthAnalysisApplication {
    @MainActor public var analysisCaffeineQuantities: [TrackingQuantity] {
        analysisNumericQuantities.filter { $0.unit.lowercased() == "mg" }
    }

    @MainActor public var analysisNumericQuantities: [TrackingQuantity] {
        manualLog.quantities
    }

    @MainActor public func analysisAdjustmentSuggestions(excluding inputIDs: [UUID]) -> [TrackingQuantity] {
        let selected = Set(inputIDs)
        return analysisNumericQuantities.filter { !selected.contains($0.id) }
    }

    @MainActor public func analyze(
        _ configuration: AnalysisConfiguration, asOf: Date = .now
    ) throws(AnalysisRunFailure) -> AnalysisResult {
        let series = configuration.inputs + configuration.adjustmentInputs
        guard case .health(let metric, let sourceID) = configuration.output,
              metric == .restingHeartRate || metric == .sleepAnalysis,
              !configuration.inputs.isEmpty, Set(series).count == series.count else { throw .unsupportedConfiguration }
        if let interaction = configuration.interaction, !interaction.isValid(for: configuration.inputs) {
            throw .unsupportedConfiguration
        }
        guard manualLog.isStoreAvailable else { throw .manualLogUnavailable }
        let availableQuantities = Dictionary(uniqueKeysWithValues: analysisNumericQuantities.map { ($0.id, $0) })
        var quantities: [TrackingQuantity] = []
        for input in series {
            guard case .manualQuantity(let quantityID) = input else { throw .unsupportedConfiguration }
            guard let quantity = availableQuantities[quantityID] else { throw .inputUnavailable }
            quantities.append(quantity)
        }

        let lastReadAt = healthMeasurements.lastSuccessfulReadAt
        let lastReadFailure: HealthMeasurementReadFailure?
        switch healthMeasurements.readState {
        case .failed(let failure):
            guard lastReadAt != nil else { throw .healthHistoryUnavailable(failure) }
            lastReadFailure = failure
        case .loading:
            guard lastReadAt != nil else { throw .healthHistoryLoading }
            lastReadFailure = nil
        case .idle, .loaded:
            lastReadFailure = nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = configuration.timeZone
        let outputs: [TemporalAnalysisDataset.Output]
        if metric == .sleepAnalysis {
            let episodes = healthMeasurements.deriveSleepEpisodes(
                from: healthMeasurements.history.filter { $0.metric == .sleepAnalysis && $0.endDate <= asOf }
            )
            outputs = TemporalAnalysisDataset.sleepDurationOutputs(episodes, asOf: asOf, calendar: calendar)
        } else {
            outputs = TemporalAnalysisDataset.restingHeartRateOutputs(
                healthMeasurements.history, asOf: asOf, calendar: calendar
            )
        }
        let outputSourceID = sourceID ?? healthMeasurements.preferredSource(for: metric)?.bundleIdentifier
        let sources = Set(outputs.map(\.source.bundleIdentifier))
        guard outputSourceID != nil || sources.count <= 1 else { throw .chooseOutputSource }
        let selectedOutputs = outputs.filter { outputSourceID == nil || $0.source.bundleIdentifier == outputSourceID }

        let dataset = TemporalAnalysisDataset(
            outputs: selectedOutputs, quantities: quantities, manualLog: manualLog,
            window: configuration.behaviorWindow, history: configuration.history, asOf: asOf, calendar: calendar
        )
        let modeledInputs = quantities.enumerated().map { index, quantity in
            AnalysisModeledInput(
                series: .manualQuantity(quantity.id), name: quantity.name, unit: quantity.unit,
                role: index < configuration.inputs.count ? .input : .adjustment,
                defaultDayCount: dataset.observations.count { $0.inputs[index].origin != .observation }
            )
        }
        let assessment = NumericAnalysis.assess(
            dataset.observations, inputs: modeledInputs, coverage: dataset.coverage, calendar: calendar,
            behaviorWindow: configuration.behaviorWindow, practicalDifference: metric == .sleepAnalysis ? 0.25 : 1,
            interaction: configuration.interaction
        )
        return AnalysisResult(
            configuration: configuration,
            outputSource: dataset.outputSource,
            healthHistoryReadAt: lastReadAt,
            lastHealthReadFailure: lastReadFailure,
            observations: dataset.observations,
            coverage: dataset.coverage,
            model: assessment.model,
            modeledInputs: modeledInputs,
            estimates: assessment.estimates,
            interaction: assessment.interaction,
            evidence: assessment.evidence
        )
    }
}
