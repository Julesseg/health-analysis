import Foundation

public struct AnalysisInspection: Codable, Sendable {
    public struct OutputWithoutPair: Codable, Identifiable, Sendable {
        public struct MissingInput: Codable, Hashable, Identifiable, Sendable {
            public var id: Self { self }
            public let series: AnalysisSeriesID
            public let date: Date
        }

        public var id: Date { date }
        public let date: Date
        public let anchor: Date
        public let value: Double
        public let source: HealthMeasurement.Source
        public let missingInputs: [MissingInput]
    }

    public let unpairedOutputs: [OutputWithoutPair]
    public let selectedOutputSourceIdentifier: String?
}

public struct AnalysisInputEvidence: Sendable {
    public struct Pair: Identifiable, Sendable {
        public var id: Date { outputDate }
        public let outputDate: Date
        public let outputValue: Double
        public let input: AnalysisObservation.Input

        public var entries: [AnalysisObservation.Input.Day] {
            input.days.isEmpty
                ? [.init(date: input.date, value: input.value, origin: input.origin)]
                : input.days
        }
    }

    public let pairs: [Pair]

    public var observedPairs: [Pair] { pairs.filter { $0.input.origin == .observation } }
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
    public func inputEvidence(for series: AnalysisSeriesID) -> AnalysisInputEvidence {
        AnalysisInputEvidence(pairs: observations.compactMap { row in
            guard let input = row.inputs.first(where: { $0.series == series }) else { return nil }
            return .init(outputDate: row.outputDate, outputValue: row.outputValue, input: input)
        })
    }
}
