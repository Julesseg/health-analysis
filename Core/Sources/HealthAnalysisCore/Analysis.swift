import Foundation

public enum AnalysisSeriesID: Codable, Hashable, Sendable {
    case manualQuantity(UUID)
    case manualTyped(UUID)
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
            public internal(set) var trackingValue: ManualTrackingValue? = nil

            public var clockPrecision: ManualClockPrecision? {
                if case .timeOfDay(_, let precision)? = trackingValue { return precision }
                return nil
            }
        }

        public let series: AnalysisSeriesID
        public let date: Date
        public let value: Double
        public let origin: ManualValueOrigin
        public let days: [Day]
        public var trackingValue: ManualTrackingValue? { days.count == 1 ? days[0].trackingValue : nil }

        var hasObservedDay: Bool { origin == .observation || days.contains { $0.origin == .observation } }

        init(series: AnalysisSeriesID, date: Date, value: Double, origin: ManualValueOrigin, days: [Day] = []) {
            self.series = series
            self.date = date
            self.value = value
            self.origin = origin
            self.days = days
        }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            series = try fields.decode(AnalysisSeriesID.self, forKey: .series)
            date = try fields.decode(Date.self, forKey: .date)
            value = try fields.decode(Double.self, forKey: .value)
            origin = try fields.decode(ManualValueOrigin.self, forKey: .origin)
            days = try fields.decodeIfPresent([Day].self, forKey: .days) ?? []
        }
    }

    public var id: Date { outputDate }
    public let outputDate: Date
    public let outputAnchor: Date
    public let outputValue: Double
    public let inputs: [Input]
    public internal(set) var outputOrigin: ManualValueOrigin? = nil
    public internal(set) var outputTrackingValue: ManualTrackingValue? = nil
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

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        usableDates = try fields.decode([Date].self, forKey: .usableDates)
        gaps = try fields.decode([Gap].self, forKey: .gaps)
        outputDaysWithoutCompleteInput = try fields.decode(Int.self, forKey: .outputDaysWithoutCompleteInput)
        outputDatesWithoutCompleteInput = try fields.decodeIfPresent([Date].self, forKey: .outputDatesWithoutCompleteInput) ?? []
        distinctBehaviorDayCount = try fields.decodeIfPresent(Int.self, forKey: .distinctBehaviorDayCount) ?? usableDates.count
        nonOverlappingWindowCount = try fields.decodeIfPresent(Int.self, forKey: .nonOverlappingWindowCount) ?? usableDates.count
    }

    init(observations: [AnalysisObservation], outputDates: [Date], calendar: Calendar) {
        usableDates = observations.map(\.outputDate)
        let usable = Set(usableDates)
        outputDatesWithoutCompleteInput = outputDates.filter { !usable.contains($0) }
        outputDaysWithoutCompleteInput = outputDatesWithoutCompleteInput.count
        var distinctDays: Set<Date> = []
        let windows = observations.compactMap { observation -> ClosedRange<Date>? in
            guard let input = observation.inputs.first else { return nil }
            distinctDays.formUnion(input.days.isEmpty ? [input.date] : input.days.map(\.date))
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
    public internal(set) var outputVariable: AnalysisVariable? = nil
    public internal(set) var inspection: AnalysisInspection? = nil
}

public enum AnalysisRunFailure: Error, Equatable {
    case unsupportedConfiguration
    case inputUnavailable
    case outputUnavailable
    case countWindowUnavailable
    case countInteractionUnavailable
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
        let series = try validatedAnalysisSeries(for: configuration)
        let inputs = series.inputs
        let output = series.output?.variable

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = configuration.timeZone
        let outputHistory: AnalysisOutputHistory
        let practicalDifference: Double
        switch configuration.output {
        case .health(let metric, let sourceID):
            outputHistory = try healthOutputs(metric: metric, sourceID: sourceID, asOf: asOf, calendar: calendar)
            practicalDifference = metric == .sleepAnalysis ? 0.25 : 1
        case .manualTyped:
            guard let manualOutput = series.output else { throw .outputUnavailable }
            outputHistory = .stored(manualOutput, in: manualLog, asOf: asOf, calendar: calendar)
            practicalDifference = 0
        case .manualQuantity:
            throw .unsupportedConfiguration
        }

        let dataset = TemporalAnalysisDataset(
            outputs: outputHistory.outputs, selectedSourceIdentifier: outputHistory.selectedSourceIdentifier,
            inputs: inputs, manualLog: manualLog,
            window: configuration.behaviorWindow, history: configuration.history, asOf: asOf, calendar: calendar
        )
        let modeledInputs = inputs.enumerated().map { index, input in
            let variable = input.variable
            return AnalysisModeledInput(
                series: variable.id, name: variable.name, unit: variable.unit,
                role: index < configuration.inputs.count ? .input : .adjustment,
                defaultDayCount: dataset.observations.count { $0.inputs[index].origin != .observation },
                kind: variable.kind
            )
        }
        let assessment: NumericAnalysis
        if output?.kind == .tracked(.count) {
            assessment = CountAnalysis.assess(
                dataset.observations, inputs: modeledInputs, coverage: dataset.coverage, calendar: calendar
            )
        } else {
            assessment = NumericAnalysis.assess(
                dataset.observations, inputs: modeledInputs, coverage: dataset.coverage, calendar: calendar,
                behaviorWindow: configuration.behaviorWindow, practicalDifference: practicalDifference,
                interaction: configuration.interaction
            )
        }
        return AnalysisResult(
            configuration: configuration,
            outputSource: dataset.outputSource,
            healthHistoryReadAt: outputHistory.healthReadAt,
            lastHealthReadFailure: outputHistory.healthReadFailure,
            observations: dataset.observations,
            coverage: dataset.coverage,
            model: assessment.model,
            modeledInputs: modeledInputs,
            estimates: assessment.estimates,
            interaction: assessment.interaction,
            evidence: assessment.evidence,
            outputVariable: output,
            inspection: dataset.inspection
        )
    }

    @MainActor func validatedAnalysisSeries(
        for configuration: AnalysisConfiguration
    ) throws(AnalysisRunFailure) -> (inputs: [ManualAnalysisSeries], output: ManualAnalysisSeries?) {
        let series = configuration.inputs + configuration.adjustmentInputs
        guard !configuration.inputs.isEmpty, Set(series).count == series.count,
              !series.contains(configuration.output) else { throw .unsupportedConfiguration }
        if let interaction = configuration.interaction, !interaction.isValid(for: configuration.inputs) {
            throw .unsupportedConfiguration
        }
        guard manualLog.isStoreAvailable else { throw .manualLogUnavailable }
        let catalog = Dictionary(uniqueKeysWithValues: manualAnalysisSeries.map { ($0.variable.id, $0) })
        var inputs: [ManualAnalysisSeries] = []
        for id in series {
            if case .health = id { throw .unsupportedConfiguration }
            guard let input = catalog[id] else { throw .inputUnavailable }
            guard input.variable.supportsInput else { throw .unsupportedConfiguration }
            inputs.append(input)
        }
        let output = catalog[configuration.output]?.variable
        if output?.kind == .tracked(.count) || inputs.contains(where: { $0.variable.kind == .tracked(.count) }) {
            guard configuration.behaviorWindow == .precedingDay else { throw .countWindowUnavailable }
            guard configuration.interaction == nil else { throw .countInteractionUnavailable }
        }

        switch configuration.output {
        case .health(let metric, _):
            guard metric == .restingHeartRate || metric == .sleepAnalysis else { throw .unsupportedConfiguration }
            return (inputs, nil)
        case .manualTyped:
            guard let series = catalog[configuration.output] else { throw .outputUnavailable }
            guard series.variable.supportsOutput else { throw .unsupportedConfiguration }
            return (inputs, series)
        case .manualQuantity:
            throw .unsupportedConfiguration
        }
    }

    @MainActor private func healthOutputs(
        metric: HealthMeasurement.Metric, sourceID: String?, asOf: Date, calendar: Calendar
    ) throws(AnalysisRunFailure) -> AnalysisOutputHistory {
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

        let outputs = healthAnalysisOutputs(for: metric, asOf: asOf, calendar: calendar)
        let outputSourceID = sourceID ?? healthMeasurements.preferredSource(for: metric)?.bundleIdentifier
        let sources = Set(outputs.compactMap { $0.source?.bundleIdentifier })
        guard outputSourceID != nil || sources.count <= 1 else { throw .chooseOutputSource }
        let selectedOutputs = outputs.filter { outputSourceID == nil || $0.source?.bundleIdentifier == outputSourceID }

        return AnalysisOutputHistory(
            outputs: selectedOutputs, healthReadAt: lastReadAt, healthReadFailure: lastReadFailure,
            selectedSourceIdentifier: outputSourceID
        )
    }

    @MainActor func healthAnalysisOutputs(
        for metric: HealthMeasurement.Metric, asOf: Date, calendar: Calendar
    ) -> [TemporalAnalysisDataset.Output] {
        switch metric {
        case .sleepAnalysis:
            let episodes = healthMeasurements.deriveSleepEpisodes(
                from: healthMeasurements.history.filter { $0.metric == metric && $0.endDate <= asOf }
            )
            return TemporalAnalysisDataset.sleepDurationOutputs(episodes, asOf: asOf, calendar: calendar)
        case .restingHeartRate:
            return TemporalAnalysisDataset.restingHeartRateOutputs(healthMeasurements.history, asOf: asOf, calendar: calendar)
        default:
            return []
        }
    }
}
