import Foundation

public struct HealthMeasurement: Codable, Equatable, Identifiable, Sendable {
    public struct Metric: RawRepresentable, Codable, Hashable, Sendable {
        public static let restingHeartRate = Self(rawValue: "restingHeartRate")

        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public enum Unit: String, Codable, Sendable {
        case beatsPerMinute
    }

    public struct Source: Codable, Equatable, Sendable {
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
    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges]
}

public struct HealthMeasurementChanges: Sendable {
    public let queryID: String
    public let anchor: Data
    public let added: [HealthMeasurement]
    public let deleted: [UUID]
    public let workouts: [HealthWorkout]

    public init(
        queryID: String,
        anchor: Data,
        added: [HealthMeasurement],
        deleted: [UUID] = [],
        workouts: [HealthWorkout] = []
    ) {
        self.queryID = queryID
        self.anchor = anchor
        self.added = added
        self.deleted = deleted
        self.workouts = workouts
    }
}

public enum HealthMeasurementReadFailure: Error, Equatable {
    case unavailable
    case protectedData
    case request
    case read
    case persistence
}
