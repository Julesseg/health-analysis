import Foundation

public enum AnalysisSeriesID: Codable, Hashable, Sendable {
    case manualQuantity(UUID)
    case manualTyped(UUID)
    case sleepTiming(SleepTiming, sourceBundleIdentifier: String? = nil)
    case activity(ActivityTrackingVariable, sourceBundleIdentifier: String? = nil)
    case health(metric: HealthMeasurement.Metric, sourceBundleIdentifier: String? = nil)
}

extension AnalysisSeriesID {
    public var sourceIdentifier: String? {
        switch self {
        case .health(_, let source), .sleepTiming(_, let source), .activity(_, let source): source
        default: nil
        }
    }

    public var seriesDefinition: Self { selectingSource(nil) }

    func selectingSource(_ source: String?) -> Self {
        switch self {
        case .health(let metric, _): .health(metric: metric, sourceBundleIdentifier: source)
        case .sleepTiming(let timing, _): .sleepTiming(timing, sourceBundleIdentifier: source)
        case .activity(let variable, _): .activity(variable, sourceBundleIdentifier: source)
        default: self
        }
    }

    var isManualQuantity: Bool {
        if case .manualQuantity = self { return true }
        return false
    }

    var usesCaffeineModel: Bool {
        switch self {
        case .health(.restingHeartRate, _), .health(.sleepAnalysis, _): true
        default: false
        }
    }

    var healthHistorySeries: Self? {
        switch self {
        case .health: self
        case .sleepTiming(_, let source): .health(metric: .sleepAnalysis, sourceBundleIdentifier: source)
        case .activity(let variable, let source): .health(metric: variable.preferenceKey, sourceBundleIdentifier: source)
        case .manualQuantity, .manualTyped: nil
        }
    }
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
    public var categories: AnalysisCategoryConfiguration?

    public init(
        output: AnalysisSeriesID,
        inputs: [AnalysisSeriesID],
        adjustmentInputs: [AnalysisSeriesID] = [],
        interaction: AnalysisInteraction? = nil,
        behaviorWindow: AnalysisBehaviorWindow = .precedingDay,
        history: AnalysisPeriod = .fullHistory,
        timeZone: TimeZone = .current,
        categories: AnalysisCategoryConfiguration? = nil
    ) {
        self.output = output
        self.inputs = inputs
        self.adjustmentInputs = adjustmentInputs
        self.interaction = interaction
        self.behaviorWindow = behaviorWindow
        self.history = history
        self.timeZone = timeZone
        self.categories = categories
    }
}

public struct AnalysisImportedRecord: Codable, Sendable {
    public let source: HealthMeasurement.Source
    public let start: Date
    public let end: Date
    public internal(set) var sleepTimeZoneEvidence: SleepEpisode.TimeZoneEvidence? = nil
}

public struct AnalysisObservation: Identifiable, Codable, Sendable {
    public struct Input: Codable, Sendable {
        public struct Day: Codable, Sendable {
            public let date: Date
            public let value: Double
            public let origin: ManualValueOrigin
            public internal(set) var trackingValue: ManualTrackingValue? = nil
            public internal(set) var importedRecord: AnalysisImportedRecord? = nil

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

    public internal(set) var sleepTimeZoneEvidence: SleepEpisode.TimeZoneEvidence? = nil

    public internal(set) var importedOutput: AnalysisImportedRecord? = nil

    public var outputClockPrecision: ManualClockPrecision? {
        if case .timeOfDay(_, let precision)? = outputTrackingValue { return precision }
        return nil
    }
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
    public internal(set) var evidence: AnalysisEvidence
    public internal(set) var outputVariable: AnalysisVariable? = nil
    public internal(set) var inspection: AnalysisInspection? = nil
    public internal(set) var categoryEvidence: AnalysisCategoryEvidence? = nil
    public internal(set) var clockIntervals: [AnalysisClockInterval]? = nil
}

public enum AnalysisRunFailure: Error, Equatable {
    case unsupportedConfiguration
    case inputUnavailable
    case outputUnavailable
    case categorySelectionUnavailable
    case categoryModelCombinationUnavailable
    case categoryWindowUnavailable
    case categoryInteractionUnavailable
    case binaryWindowUnavailable
    case binaryInteractionUnavailable
    case clockWindowUnavailable
    case clockInteractionUnavailable
    case countWindowUnavailable
    case countInteractionUnavailable
    case ratingWindowUnavailable
    case ratingInteractionUnavailable
    case manualLogUnavailable
    case chooseOutputSource
    case chooseInputSource(AnalysisSeriesID)
    case healthHistoryUnavailable(HealthMeasurementReadFailure)
    case healthHistoryLoading
}

extension HealthAnalysisApplication {
    @MainActor public var analysisCaffeineQuantities: [TrackingQuantity] {
        manualLog.quantities.filter { manualLog.suggestion(for: $0.id, named: $0.name) == .caffeine && $0.unit.lowercased() == "mg" }
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
        try prepareAnalysis(configuration, asOf: asOf)()
    }

    @MainActor func prepareAnalysis(
        _ configuration: AnalysisConfiguration, asOf: Date, after cutoff: Date? = nil,
        interactionReference: AnalysisInteractionEstimate? = nil, legacyCaffeineInput: AnalysisSeriesID? = nil
    ) throws(AnalysisRunFailure) -> PreparedAnalysis {
        let (variables, output, category) = try validatedAnalysisSeries(for: configuration)
        let inputs = variables.map { variable in
            guard variable.id == legacyCaffeineInput else { return variable }
            var legacy = variable
            legacy.isCaffeineQuantity = true
            return legacy
        }
        let manual = Dictionary(uniqueKeysWithValues: manualAnalysisSeries.map { ($0.variable.id, $0) })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = configuration.timeZone
        let outputHistory: AnalysisOutputHistory
        let practicalDifference: Double
        if let series = manual[configuration.output] {
            outputHistory = .stored(
                series, in: manualLog, asOf: asOf, calendar: calendar, categoryEvent: category.outputEvent
            )
            practicalDifference = 0
        } else {
            outputHistory = try importedAnalysisHistory(
                for: configuration.output, asOf: asOf, calendar: calendar, asInput: false
            )
            practicalDifference = switch configuration.output {
            case .health(.sleepAnalysis, _): 0.25
            case .health(.restingHeartRate, _): 1
            default: 0
            }
        }

        var importedInputs: [AnalysisSeriesID: [Date: AnalysisObservation.Input.Day]] = [:]
        var readAt = outputHistory.healthReadAt
        var readFailure = outputHistory.healthReadFailure
        for input in inputs where input.id.healthHistorySeries != nil {
            let history = try importedAnalysisHistory(for: input.id, asOf: asOf, calendar: calendar, asInput: true)
            importedInputs[input.id] = history.inputDays(calendar: calendar)
            readAt = history.healthReadAt ?? readAt
            readFailure = history.healthReadFailure ?? readFailure
        }
        let dataset = TemporalAnalysisDataset(
            outputs: outputHistory.outputs, selectedSourceIdentifier: outputHistory.selectedSourceIdentifier,
            inputs: inputs.map(\.id), manualInputs: manual, importedInputs: importedInputs, manualLog: manualLog,
            window: configuration.behaviorWindow, history: configuration.history, asOf: asOf, calendar: calendar,
            categoryInputs: category.inputContrasts, after: cutoff
        )
        return { [calendar, readAt, readFailure] in
            AnalysisResult.assess(
                configuration: configuration, dataset: dataset, inputs: inputs,
                output: configuration.output.usesCaffeineModel ? nil : output,
                calendar: calendar, practicalDifference: practicalDifference,
                lastReadAt: readAt, lastReadFailure: readFailure,
                category: category, interactionReference: interactionReference
            )
        }
    }

    @MainActor func validatedAnalysisSeries(
        for configuration: AnalysisConfiguration
    ) throws(AnalysisRunFailure) -> (inputs: [AnalysisVariable], output: AnalysisVariable, category: CategoryAnalysis) {
        let series = configuration.inputs + configuration.adjustmentInputs
        let definitions = series.map(\.seriesDefinition)
        guard !configuration.inputs.isEmpty, Set(definitions).count == series.count,
              !definitions.contains(configuration.output.seriesDefinition) else { throw .unsupportedConfiguration }
        if let interaction = configuration.interaction, !interaction.isValid(for: configuration.inputs) {
            throw .unsupportedConfiguration
        }
        if (series + [configuration.output]).contains(where: { $0.healthHistorySeries == nil }) {
            guard manualLog.isStoreAvailable else { throw .manualLogUnavailable }
        }
        var inputs: [AnalysisVariable] = []
        for id in series {
            guard let input = analysisVariable(for: id) else {
                throw id.healthHistorySeries == nil ? .inputUnavailable : .unsupportedConfiguration
            }
            guard input.supportsInput else { throw .unsupportedConfiguration }
            inputs.append(input)
        }
        guard let output = analysisVariable(for: configuration.output) else {
            throw configuration.output.healthHistorySeries == nil ? .outputUnavailable : .unsupportedConfiguration
        }
        guard output.supportsOutput else { throw .unsupportedConfiguration }
        let category = try CategoryAnalysis(configuration: configuration, inputs: inputs, output: output)
        try AnalysisCapabilities(variables: inputs + [output]).validate(configuration)
        return (inputs, output, category)
    }

    @MainActor private func importedAnalysisHistory(
        for id: AnalysisSeriesID, asOf: Date, calendar: Calendar, asInput: Bool
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

        let (outputs, preferred) = importedAnalysisOutputs(for: id, asOf: asOf, calendar: calendar)
        let sourceID = id.sourceIdentifier ?? preferred
        let sources = Set(outputs.compactMap { $0.source?.bundleIdentifier })
        guard sourceID != nil || sources.count <= 1 else {
            throw asInput ? .chooseInputSource(id) : .chooseOutputSource
        }
        let selected = outputs.filter { sourceID == nil || $0.source?.bundleIdentifier == sourceID }
        return AnalysisOutputHistory(
            outputs: selected, healthReadAt: lastReadAt, healthReadFailure: lastReadFailure,
            selectedSourceIdentifier: sourceID
        )
    }

    @MainActor func importedAnalysisOutputs(
        for id: AnalysisSeriesID, asOf: Date, calendar: Calendar
    ) -> ([TemporalAnalysisDataset.Output], preferred: String?) {
        switch id {
        case .health(let metric, _):
            return (healthAnalysisOutputs(for: metric, asOf: asOf, calendar: calendar),
                    healthMeasurements.preferredSource(for: metric)?.bundleIdentifier)
        case .sleepTiming(let timing, _):
            return (healthAnalysisOutputs(for: .sleepAnalysis, asOf: asOf, calendar: calendar, timing: timing),
                    healthMeasurements.preferredSource(for: .sleepAnalysis)?.bundleIdentifier)
        case .activity(let variable, _):
            let workouts = healthMeasurements.workouts.filter {
                variable.includes($0) && $0.startDate <= $0.endDate && $0.endDate <= asOf
            }
            let bySource = Dictionary(grouping: workouts) { $0.source.bundleIdentifier }
            let today = calendar.startOfDay(for: asOf)
            let outputs = bySource.keys.sorted().flatMap { source in
                TemporalAnalysisDataset.activityOutputs(bySource[source] ?? [], variable: variable, calendar: calendar)
                    .filter { $0.date < today }
            }
            return (outputs, healthMeasurements.preferredWorkoutSource(for: variable)?.bundleIdentifier)
        default:
            return ([], nil)
        }
    }

    @MainActor func healthAnalysisOutputs(
        for metric: HealthMeasurement.Metric, asOf: Date, calendar: Calendar, timing: SleepTiming? = nil
    ) -> [TemporalAnalysisDataset.Output] {
        switch metric {
        case .sleepAnalysis:
            let episodes = healthMeasurements.deriveSleepEpisodes(
                from: healthMeasurements.history.filter { $0.metric == metric && $0.endDate <= asOf }
            )
            return TemporalAnalysisDataset.sleepOutputs(episodes, asOf: asOf, calendar: calendar, timing: timing)
        case .restingHeartRate:
            return TemporalAnalysisDataset.restingHeartRateOutputs(healthMeasurements.history, asOf: asOf, calendar: calendar)
        default:
            return []
        }
    }
}

typealias PreparedAnalysis = @Sendable () -> AnalysisResult

extension AnalysisResult {
    static func assess(
        configuration: AnalysisConfiguration, dataset: TemporalAnalysisDataset, inputs: [AnalysisVariable],
        output: AnalysisVariable? = nil, calendar: Calendar, practicalDifference: Double,
        lastReadAt: Date?, lastReadFailure: HealthMeasurementReadFailure? = nil, exploratory: Bool = false,
        category: CategoryAnalysis? = nil, interactionReference: AnalysisInteractionEstimate? = nil
    ) -> Self {
        let modeledInputs = inputs.enumerated().map { index, variable in
            return AnalysisModeledInput(
                series: variable.id, name: variable.name, unit: variable.unit,
                role: index < configuration.inputs.count ? .input : .adjustment,
                defaultDayCount: dataset.observations.count { $0.inputs[index].origin != .observation },
                kind: variable.kind, isCaffeineQuantity: variable.isCaffeineQuantity
            )
        }
        let categoryEvidence = category?.summarize(dataset, inputs: inputs, output: output)
        let outputIsClock = output?.kind == .tracked(.timeOfDay)
        let ratingOutputThreshold = output?.kind.ratingThreshold
        let usesRatings = ratingOutputThreshold != nil || inputs.contains { $0.kind.ratingThreshold != nil }
        let model: AnalysisModel
        if category?.outputEvent != nil {
            model = .categoryEventLogisticV1
        } else {
            model = switch output?.kind {
            case .tracked(.count): .countLogLinearV1
            case .tracked(.yesNo): .binaryLogisticV1
            default: usesRatings ? .ratingThresholdLinearV1 : .numericLinearV1
            }
        }

        func fit(_ rows: [AnalysisObservation]) -> NumericAnalysis {
            if let categoryEvidence, model == .categoryEventLogisticV1 {
                return CategoryEventAnalysis.assess(
                    rows, inputs: modeledInputs, coverage: dataset.coverage,
                    categoryEvidence: categoryEvidence, calendar: calendar
                )
            }
            switch model {
            case .countLogLinearV1:
                return CountAnalysis.assess(rows, inputs: modeledInputs, coverage: dataset.coverage, calendar: calendar)
            case .binaryLogisticV1:
                return BinaryAnalysis.assess(rows, inputs: modeledInputs, coverage: dataset.coverage, calendar: calendar)
            default:
                return NumericAnalysis.assess(
                    rows, inputs: modeledInputs, coverage: dataset.coverage, calendar: calendar,
                    behaviorWindow: configuration.behaviorWindow, practicalDifference: practicalDifference,
                    interaction: configuration.interaction, ratingOutputThreshold: ratingOutputThreshold,
                    outputIsClock: outputIsClock, interactionReference: interactionReference,
                    usesCaffeineModel: configuration.output.usesCaffeineModel,
                    hasManualQuantityOutput: configuration.output.isManualQuantity
                )
            }
        }

        func assess(_ rows: [AnalysisObservation]) -> NumericAnalysis {
            guard let categoryEvidence else { return fit(rows) }
            return CategoryAnalysis.assessInputContrasts(
                categoryEvidence, observations: rows, assessment: { fit(rows) }, model: model
            )
        }

        let assessment: NumericAnalysis
        let clockIntervals: [AnalysisClockInterval]?
        if outputIsClock || inputs.contains(where: { $0.kind == .tracked(.timeOfDay) }) {
            (assessment, clockIntervals) = ClockAnalysis.assess(
                dataset.observations, inputs: modeledInputs, output: configuration.output, outputIsClock: outputIsClock,
                model: model, fit: assess
            )
        } else {
            assessment = assess(dataset.observations)
            clockIntervals = nil
        }
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
            evidence: exploratory && assessment.evidence.grade != .insufficient
                ? AnalysisEvidence(
                    grade: .low, reasons: assessment.evidence.reasons,
                    defaultDayCount: assessment.evidence.defaultDayCount,
                    dependenceLagDays: assessment.evidence.dependenceLagDays
                )
                : assessment.evidence,
            outputVariable: output,
            inspection: dataset.inspection,
            categoryEvidence: categoryEvidence,
            clockIntervals: clockIntervals
        )
    }

}
