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
    public let firstUse: FirstUseSetup
    public let discovery: DiscoveryActivity
    let analysisFitter = AnalysisFitter()

    public init(
        healthSource: (any HealthMeasurementSource)? = nil,
        healthHistoryStoreURL: URL? = nil,
        manualLogStoreURL: URL? = nil,
        legacyManualLogStoreURL: URL? = nil,
        savedAnalysesStoreURL: URL? = nil,
        firstUseStoreURL: URL? = nil,
        discoveryPreferencesKey: String? = nil
    ) {
        healthMeasurements = HealthMeasurementHistory(source: healthSource, storeURL: healthHistoryStoreURL)
        manualLog = ManualLog(storeURL: manualLogStoreURL, legacyURL: legacyManualLogStoreURL)
        savedAnalyses = SavedAnalyses(storeURL: savedAnalysesStoreURL)
        discovery = DiscoveryActivity(preferencesKey: discoveryPreferencesKey)
        firstUse = FirstUseSetup(health: healthMeasurements, storeURL: firstUseStoreURL)
    }

    @MainActor public var overview: Overview {
        Overview(
            hasReadableMeasurements: healthMeasurements.hasReadableRecords,
            hasTrackingVariables: !manualLog.quantities.isEmpty || !manualLog.typedVariables.isEmpty,
            hasFollowedAnalyses: !savedAnalyses.following.isEmpty,
            hasDiscoveries: discovery.report?.findings.isEmpty == false
        )
    }
}
