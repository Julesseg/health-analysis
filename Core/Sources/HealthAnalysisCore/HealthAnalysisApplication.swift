public struct HealthAnalysisApplication: Sendable {
    public struct Overview: Sendable {
        public let hasReadableMeasurements: Bool
        public let hasTrackingVariables: Bool
        public let hasFollowedAnalyses: Bool
        public let hasDiscoveries: Bool
    }

    public let overview: Overview

    public init() {
        overview = Overview(
            hasReadableMeasurements: false,
            hasTrackingVariables: false,
            hasFollowedAnalyses: false,
            hasDiscoveries: false
        )
    }
}
