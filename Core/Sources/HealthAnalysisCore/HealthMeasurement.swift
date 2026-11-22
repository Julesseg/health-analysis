import Foundation

public struct HealthMeasurement: Equatable, Identifiable, Sendable {
    public enum Metric: Sendable {
        case restingHeartRate
    }

    public enum Unit: Sendable {
        case beatsPerMinute
    }

    public struct Source: Equatable, Sendable {
        public let name: String
        public let bundleIdentifier: String

        public init(name: String, bundleIdentifier: String) {
            self.name = name
            self.bundleIdentifier = bundleIdentifier
        }
    }

    public let id: UUID
    public let metric: Metric
    public let value: Double
    public let unit: Unit
    public let startDate: Date
    public let endDate: Date
    public let source: Source

    public init(
        id: UUID,
        metric: Metric,
        value: Double,
        unit: Unit,
        startDate: Date,
        endDate: Date,
        source: Source
    ) {
        self.id = id
        self.metric = metric
        self.value = value
        self.unit = unit
        self.startDate = startDate
        self.endDate = endDate
        self.source = source
    }
}

public protocol HealthMeasurementSource: Sendable {
    func requestReadAccess() async throws
    func readMeasurements() async throws -> [HealthMeasurement]
}

public enum HealthMeasurementReadFailure: Error, Equatable {
    case unavailable
    case protectedData
    case request
    case read
}
