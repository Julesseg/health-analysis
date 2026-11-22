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
    public let savedAnalyses: SavedAnalyses

    public init(
        healthSource: (any HealthMeasurementSource)? = nil,
        healthHistoryStoreURL: URL? = nil,
        manualLogStoreURL: URL? = nil,
        savedAnalysesStoreURL: URL? = nil
    ) {
        healthMeasurements = HealthMeasurementHistory(source: healthSource, storeURL: healthHistoryStoreURL)
        manualLog = ManualLog(storeURL: manualLogStoreURL)
        savedAnalyses = SavedAnalyses(storeURL: savedAnalysesStoreURL)
    }

    @MainActor public var overview: Overview {
        Overview(
            hasReadableMeasurements: healthMeasurements.hasReadableRecords,
            hasTrackingVariables: !manualLog.quantities.isEmpty || !manualLog.typedVariables.isEmpty,
            hasFollowedAnalyses: !savedAnalyses.following.isEmpty,
            hasDiscoveries: false
        )
    }
}
