import Foundation

public struct AnalysisInspection: Codable, Sendable {
    public struct OutputWithoutPair: Codable, Identifiable, Sendable {
        public struct MissingInput: Codable, Hashable, Identifiable, Sendable {
            public var id: Self { self }
            public let series: AnalysisSeriesID
            public let date: Date
        }

        public struct ExcludedCategoryInput: Codable, Identifiable, Sendable {
            public var id: AnalysisSeriesID { series }
            public let series: AnalysisSeriesID
            public let date: Date
            public let category: TrackingCategory.ID
            public let origin: ManualValueOrigin
        }

        public var id: Date { date }
        public let date: Date
        public let anchor: Date
        public let value: Double
        public let source: HealthMeasurement.Source?
        public let missingInputs: [MissingInput]
        public internal(set) var origin: ManualValueOrigin? = nil
        public internal(set) var trackingValue: ManualTrackingValue? = nil
        public internal(set) var excludedCategoryInputs: [ExcludedCategoryInput]? = nil
        public internal(set) var sleepTimeZoneEvidence: SleepEpisode.TimeZoneEvidence? = nil
    }

    public let unpairedOutputs: [OutputWithoutPair]
    public let selectedOutputSourceIdentifier: String?
}

public struct AnalysisOutputEvidence: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let anchor: Date
    public let value: Double
    public let source: HealthMeasurement.Source?
    public let origin: ManualValueOrigin?
    public let trackingValue: ManualTrackingValue?
    public let paired: Bool
    public let sleepTimeZoneEvidence: SleepEpisode.TimeZoneEvidence?
    public internal(set) var excludedByCategory: Bool = false

    public var clockPrecision: ManualClockPrecision? {
        if case .timeOfDay(_, let precision)? = trackingValue { return precision }
        return nil
    }

    public var isObserved: Bool { origin == nil || origin == .observation }
}

public struct AnalysisInputEvidence: Sendable {
    public struct Pair: Identifiable, Sendable {
        public var id: Date { outputDate }
        public let outputDate: Date
        public let outputValue: Double
        public let outputOrigin: ManualValueOrigin?
        public let outputTrackingValue: ManualTrackingValue?
        public let outputAnchor: Date
        public let sleepTimeZoneEvidence: SleepEpisode.TimeZoneEvidence?
        public let input: AnalysisObservation.Input

        public var entries: [AnalysisObservation.Input.Day] {
            input.days.isEmpty
                ? [.init(date: input.date, value: input.value, origin: input.origin)]
                : input.days
        }
    }

    public let pairs: [Pair]

    public var observedPairs: [Pair] {
        pairs.filter { $0.input.origin == .observation && ($0.outputOrigin == nil || $0.outputOrigin == .observation) }
    }
    public var explicitCount: Int { pairs.count { $0.input.origin == .observation } }
    public var assumedDefaultCount: Int { pairs.count - explicitCount }
    public var distinctEntries: [AnalysisObservation.Input.Day] {
        var entries: [Date: AnalysisObservation.Input.Day] = [:]
        for pair in pairs {
            for entry in pair.entries { entries[entry.date] = entry }
        }
        return entries.values.sorted { $0.date < $1.date }
    }

    public var approximateCount: Int? {
        let precisions = distinctEntries.compactMap(\.clockPrecision)
        guard !precisions.isEmpty else { return nil }
        return precisions.count { $0 == .approximate }
    }
}

extension AnalysisResult {
    public var outputEvidence: [AnalysisOutputEvidence] {
        let paired = observations.map {
            AnalysisOutputEvidence(
                date: $0.outputDate, anchor: $0.outputAnchor, value: $0.outputValue, source: outputSource,
                origin: $0.outputOrigin, trackingValue: $0.outputTrackingValue, paired: true,
                sleepTimeZoneEvidence: $0.sleepTimeZoneEvidence
            )
        }
        let unpaired = (inspection?.unpairedOutputs ?? []).map {
            AnalysisOutputEvidence(
                date: $0.date, anchor: $0.anchor, value: $0.value, source: $0.source,
                origin: $0.origin, trackingValue: $0.trackingValue, paired: false,
                sleepTimeZoneEvidence: $0.sleepTimeZoneEvidence,
                excludedByCategory: $0.excludedCategoryInputs != nil
            )
        }
        return (paired + unpaired).sorted { $0.date < $1.date }
    }

    public func inputEvidence(for series: AnalysisSeriesID) -> AnalysisInputEvidence {
        AnalysisInputEvidence(pairs: observations.compactMap { row in
            guard let input = row.inputs.first(where: { $0.series == series }) else { return nil }
            return .init(
                outputDate: row.outputDate, outputValue: row.outputValue,
                outputOrigin: row.outputOrigin, outputTrackingValue: row.outputTrackingValue,
                outputAnchor: row.outputAnchor, sleepTimeZoneEvidence: row.sleepTimeZoneEvidence, input: input
            )
        })
    }
}
