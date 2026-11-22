import Foundation

public struct HealthAnalysisApplication: Sendable {
    public struct Overview: Sendable {
        public let hasReadableMeasurements: Bool
        public let hasTrackingVariables: Bool
        public let hasFollowedAnalyses: Bool
        public let hasDiscoveries: Bool
    }

    public let manualLog: ManualLog

    public init(manualLogStoreURL: URL? = nil) {
        manualLog = ManualLog(storeURL: manualLogStoreURL)
    }

    @MainActor public var overview: Overview {
        Overview(
            hasReadableMeasurements: false,
            hasTrackingVariables: !manualLog.quantities.isEmpty,
            hasFollowedAnalyses: false,
            hasDiscoveries: false
        )
    }
}
