import Foundation

public enum AnalysisSeriesID: Codable, Hashable, Sendable {
    case manualQuantity(UUID)
    case manualTyped(UUID)
    case health(metric: HealthMeasurement.Metric, sourceBundleIdentifier: String? = nil)
}

public enum AnalysisBehaviorWindow: String, Codable, Hashable, Sendable {
    case precedingDay
}

public enum AnalysisPeriod: String, Codable, Hashable, Sendable {
    case fullHistory
}

public struct AnalysisConfiguration: Codable, Hashable, Sendable {
    public var output: AnalysisSeriesID
    public var inputs: [AnalysisSeriesID]
    public var adjustmentInputs: [AnalysisSeriesID]
    public var behaviorWindow: AnalysisBehaviorWindow
    public var history: AnalysisPeriod
    public var timeZone: TimeZone

    public init(
        output: AnalysisSeriesID,
        inputs: [AnalysisSeriesID],
        adjustmentInputs: [AnalysisSeriesID] = [],
        behaviorWindow: AnalysisBehaviorWindow = .precedingDay,
        history: AnalysisPeriod = .fullHistory,
        timeZone: TimeZone = .current
    ) {
        self.output = output
        self.inputs = inputs
        self.adjustmentInputs = adjustmentInputs
        self.behaviorWindow = behaviorWindow
        self.history = history
        self.timeZone = timeZone
    }
}

public struct AnalysisObservation: Identifiable, Codable, Sendable {
    public struct Input: Codable, Sendable {
        public let series: AnalysisSeriesID
        public let date: Date
        public let value: Double
        public let origin: ManualValueOrigin
        public internal(set) var trackingValue: ManualTrackingValue? = nil
    }

    public var id: Date { outputDate }
    public let outputDate: Date
    public let outputAnchor: Date
    public let outputValue: Double
    public let inputs: [Input]
    public let outputOrigin: ManualValueOrigin?
    public let outputTrackingValue: ManualTrackingValue?

    init(
        outputDate: Date, outputAnchor: Date, outputValue: Double,
        inputs: [Input], outputOrigin: ManualValueOrigin? = nil, outputTrackingValue: ManualTrackingValue? = nil
    ) {
        self.outputDate = outputDate
        self.outputAnchor = outputAnchor
        self.outputValue = outputValue
        self.inputs = inputs
        self.outputOrigin = outputOrigin
        self.outputTrackingValue = outputTrackingValue
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

    public var firstDate: Date? { usableDates.first }
    public var lastDate: Date? { usableDates.last }
    public var missingDays: Int { gaps.reduce(0) { $0 + $1.dayCount } }

    init(observations: [AnalysisObservation], outputDays: Int, calendar: Calendar) {
        usableDates = observations.map(\.outputDate)
        outputDaysWithoutCompleteInput = outputDays - usableDates.count
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
    public let evidence: AnalysisEvidence
    public internal(set) var outputVariable: AnalysisVariable? = nil
}

public enum AnalysisRunFailure: Error, Equatable {
    case unsupportedConfiguration
    case inputUnavailable
    case outputUnavailable
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
        guard !configuration.inputs.isEmpty, Set(series).count == series.count,
              !series.contains(configuration.output), configuration.behaviorWindow == .precedingDay,
              configuration.history == .fullHistory else { throw .unsupportedConfiguration }
        guard manualLog.isStoreAvailable else { throw .manualLogUnavailable }
        let catalog = Dictionary(uniqueKeysWithValues: manualAnalysisSeries.map { ($0.variable.id, $0) })
        var inputs: [ManualAnalysisSeries] = []
        for id in series {
            if case .health = id { throw .unsupportedConfiguration }
            guard let input = catalog[id] else { throw .inputUnavailable }
            guard input.variable.supportsInput else { throw .unsupportedConfiguration }
            inputs.append(input)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = configuration.timeZone
        let outputHistory: AnalysisOutputHistory
        let output: AnalysisVariable?
        switch configuration.output {
        case .health(let metric, let sourceID):
            guard metric == .restingHeartRate else { throw .unsupportedConfiguration }
            outputHistory = try restingHeartRateOutput(sourceID: sourceID, asOf: asOf, calendar: calendar)
            output = nil
        case .manualTyped:
            guard let manualOutput = catalog[configuration.output] else { throw .outputUnavailable }
            guard manualOutput.variable.supportsOutput else { throw .unsupportedConfiguration }
            outputHistory = .stored(manualOutput, in: manualLog, asOf: asOf, calendar: calendar)
            output = manualOutput.variable
        case .manualQuantity:
            throw .unsupportedConfiguration
        }

        let dataset = DailyQuantityDataset(
            outputHistory: outputHistory, inputs: inputs, manualLog: manualLog, calendar: calendar
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
                dataset.observations, inputs: modeledInputs, coverage: dataset.coverage, calendar: calendar
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
            evidence: assessment.evidence,
            outputVariable: output
        )
    }

    @MainActor private func restingHeartRateOutput(
        sourceID: String?, asOf: Date, calendar: Calendar
    ) throws(AnalysisRunFailure) -> AnalysisOutputHistory {
        let metric = HealthMeasurement.Metric.restingHeartRate
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

        let records = healthMeasurements.history.filter {
            $0.metric == metric && $0.unit == .beatsPerMinute && $0.value.isFinite && $0.value > 0
                && $0.startDate <= $0.endDate && $0.endDate <= asOf
        }
        let outputSourceID = sourceID ?? healthMeasurements.preferredSource(for: metric)?.bundleIdentifier
        let sources = Set(records.map(\.source.bundleIdentifier))
        guard outputSourceID != nil || sources.count <= 1 else { throw .chooseOutputSource }
        let outputRecords = records.filter { outputSourceID == nil || $0.source.bundleIdentifier == outputSourceID }

        return .restingHeartRate(outputRecords, readAt: lastReadAt, failure: lastReadFailure, calendar: calendar)
    }
}

private struct DailyQuantityDataset {
    let observations: [AnalysisObservation]
    let coverage: AnalysisCoverage
    let outputSource: HealthMeasurement.Source?

    @MainActor init(
        outputHistory: AnalysisOutputHistory, inputs: [ManualAnalysisSeries], manualLog: ManualLog, calendar: Calendar
    ) {
        let dailyOutputs = outputHistory.days
        observations = dailyOutputs.keys.sorted().compactMap { date -> AnalysisObservation? in
            guard let output = dailyOutputs[date],
                  let preceding = calendar.dateInterval(of: .day, for: date.addingTimeInterval(-1))?.start else {
                return nil
            }
            let inputDay = ManualLogDay(preceding, timeZone: calendar.timeZone)
            var values: [AnalysisObservation.Input] = []
            for input in inputs {
                guard let sample = input.numericValue(in: manualLog, on: inputDay) else { return nil }
                values.append(.init(
                    series: input.variable.id, date: preceding, value: sample.value,
                    origin: sample.origin, trackingValue: sample.trackingValue
                ))
            }
            return AnalysisObservation(
                outputDate: date, outputAnchor: output.anchor, outputValue: output.value,
                inputs: values, outputOrigin: output.origin, outputTrackingValue: output.trackingValue
            )
        }
        coverage = AnalysisCoverage(observations: observations, outputDays: dailyOutputs.count, calendar: calendar)
        outputSource = observations.last.flatMap { dailyOutputs[$0.outputDate]?.source }
    }
}
