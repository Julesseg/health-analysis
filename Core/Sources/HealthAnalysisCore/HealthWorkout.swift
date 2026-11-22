import Foundation

public struct HealthWorkout: Codable, Equatable, Identifiable, Sendable {
    public enum Activity: Codable, Hashable, Sendable {
        case running
        case other(healthKitType: UInt)
    }

    public let id: UUID
    public let activity: Activity
    public let startDate: Date
    public let endDate: Date
    public let activeDurationSeconds: Double
    public let runningDistanceMeters: Double?
    public let source: HealthMeasurement.Source
    public let sourceVersion: String?
    public let sourceProductType: String?
    public let timeZoneIdentifier: String?

    public init(
        id: UUID,
        activity: Activity,
        startDate: Date,
        endDate: Date,
        activeDurationSeconds: Double,
        runningDistanceMeters: Double?,
        source: HealthMeasurement.Source,
        sourceVersion: String? = nil,
        sourceProductType: String? = nil,
        timeZoneIdentifier: String? = nil
    ) {
        self.id = id
        self.activity = activity
        self.startDate = startDate
        self.endDate = endDate
        self.activeDurationSeconds = activeDurationSeconds
        self.runningDistanceMeters = runningDistanceMeters
        self.source = source
        self.sourceVersion = sourceVersion
        self.sourceProductType = sourceProductType
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}
