import Foundation

public enum AnalysisSeriesID: Codable, Hashable, Sendable {
    case manualQuantity(UUID)
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
    public let estimates: [AnalysisEstimate]
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
        manualLog.quantities.filter { $0.unit.lowercased() == "mg" }
    }

    @MainActor public func analyze(
        _ configuration: AnalysisConfiguration, asOf: Date = .now
    ) throws(AnalysisRunFailure) -> AnalysisResult {
        guard case .health(let metric, let sourceID) = configuration.output, metric == .restingHeartRate,
              configuration.inputs.count == 1, case .manualQuantity(let quantityID) = configuration.inputs[0],
              configuration.adjustmentInputs.isEmpty, configuration.behaviorWindow == .precedingDay,
              configuration.history == .fullHistory else { throw .unsupportedConfiguration }
        guard manualLog.isStoreAvailable else { throw .manualLogUnavailable }
        guard let quantity = analysisCaffeineQuantities.first(where: { $0.id == quantityID }) else {
            throw .inputUnavailable
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

        let records = healthMeasurements.history.filter {
            $0.metric == metric && $0.unit == .beatsPerMinute && $0.value.isFinite && $0.value > 0
                && $0.startDate <= $0.endDate && $0.endDate <= asOf
        }
        let outputSourceID = sourceID ?? healthMeasurements.preferredSource(for: metric)?.bundleIdentifier
        let sources = Set(records.map(\.source.bundleIdentifier))
        guard outputSourceID != nil || sources.count <= 1 else { throw .chooseOutputSource }
        let outputRecords = records.filter { outputSourceID == nil || $0.source.bundleIdentifier == outputSourceID }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = configuration.timeZone
        let dataset = DailyCaffeineDataset(
            records: outputRecords, quantity: quantity, manualLog: manualLog, calendar: calendar
        )
        let assessment = NumericAssociation.assess(dataset.observations, coverage: dataset.coverage, calendar: calendar)
        return AnalysisResult(
            configuration: configuration,
            outputSource: dataset.outputSource,
            healthHistoryReadAt: lastReadAt,
            lastHealthReadFailure: lastReadFailure,
            observations: dataset.observations,
            coverage: dataset.coverage,
            estimates: assessment.estimate.map { [$0] } ?? [],
            evidence: assessment.evidence
        )
    }
}

private struct DailyCaffeineDataset {
    let observations: [AnalysisObservation]
    let coverage: AnalysisCoverage
    let outputSource: HealthMeasurement.Source?

    @MainActor init(
        records: [HealthMeasurement], quantity: TrackingQuantity, manualLog: ManualLog, calendar: Calendar
    ) {
        var dailyOutputs: [Date: HealthMeasurement] = [:]
        for record in records {
            let date = calendar.startOfDay(for: record.startDate)
            if let existing = dailyOutputs[date],
               (existing.startDate, existing.endDate, existing.id.uuidString)
                <= (record.startDate, record.endDate, record.id.uuidString) {
                continue
            }
            dailyOutputs[date] = record
        }

        observations = dailyOutputs.keys.sorted().compactMap { date -> AnalysisObservation? in
            guard let record = dailyOutputs[date],
                  let preceding = calendar.dateInterval(of: .day, for: date.addingTimeInterval(-1))?.start,
                  let (amount, origin) = manualLog.analysisValue(
                      for: quantity, on: ManualLogDay(preceding, timeZone: calendar.timeZone)
                  ) else { return nil }
            let value = NSDecimalNumber(decimal: amount).doubleValue
            guard value.isFinite, value >= 0 else { return nil }
            return AnalysisObservation(
                outputDate: date, outputAnchor: record.startDate, outputValue: record.value,
                inputs: [.init(series: .manualQuantity(quantity.id), date: preceding, value: value, origin: origin)]
            )
        }
        coverage = AnalysisCoverage(observations: observations, outputDays: dailyOutputs.count, calendar: calendar)
        outputSource = observations.last.flatMap { dailyOutputs[$0.outputDate]?.source }
    }
}
