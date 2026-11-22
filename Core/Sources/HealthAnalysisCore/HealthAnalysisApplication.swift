import Foundation

public struct HealthAnalysisApplication: Sendable {
    public struct Overview: Sendable {
        public let hasReadableMeasurements: Bool
        public let hasTrackingVariables: Bool
        public let hasFollowedAnalyses: Bool
        public let hasDiscoveries: Bool
    }

    public let healthMeasurements: HealthMeasurementHistory
    public let manualLog: ManualLog

    public init(
        healthSource: (any HealthMeasurementSource)? = nil,
        healthHistoryStoreURL: URL? = nil,
        manualLogStoreURL: URL? = nil
    ) {
        healthMeasurements = HealthMeasurementHistory(source: healthSource, storeURL: healthHistoryStoreURL)
        manualLog = ManualLog(storeURL: manualLogStoreURL)
    }

    @MainActor public var overview: Overview {
        Overview(
            hasReadableMeasurements: !healthMeasurements.history.isEmpty,
            hasTrackingVariables: !manualLog.quantities.isEmpty || !manualLog.typedVariables.isEmpty,
            hasFollowedAnalyses: false,
            hasDiscoveries: false
        )
    }
}
