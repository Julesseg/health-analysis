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

    public struct WindowOverlap: Codable, Sendable {
        public let distinctBehaviorDays: Int
        public let nonOverlappingWindows: Int
    }

    public let unpairedOutputs: [OutputWithoutPair]
    public let windowOverlap: WindowOverlap
    public let selectedOutputSourceIdentifier: String?
}

public struct AnalysisInputEvidence: Sendable {
    public struct Pair: Identifiable, Sendable {
        public var id: Date { outputDate }
        public let outputDate: Date
        public let outputValue: Double
        public let input: AnalysisObservation.Input
    }

    public let pairs: [Pair]

    public var observedPairs: [Pair] { pairs.filter { $0.input.origin == .observation } }
    public var explicitCount: Int { pairs.count { $0.input.origin == .observation } }
    public var assumedDefaultCount: Int { pairs.count - explicitCount }
    public var approximateCount: Int? {
        let precisions = pairs.compactMap(\.input.clockPrecision)
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
