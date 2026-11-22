public struct HealthAnalysisApplication: Sendable {
    public struct Overview: Sendable {
        public let hasReadableMeasurements: Bool
        public let hasTrackingVariables: Bool
        public let hasFollowedAnalyses: Bool
        public let hasDiscoveries: Bool
    }

    public let healthMeasurements: HealthMeasurementHistory

    public init(healthSource: (any HealthMeasurementSource)? = nil) {
        healthMeasurements = HealthMeasurementHistory(source: healthSource)
    }

    @MainActor public var overview: Overview {
        Overview(
            hasReadableMeasurements: !healthMeasurements.history.isEmpty,
            hasTrackingVariables: false,
            hasFollowedAnalyses: false,
            hasDiscoveries: false
        )
    }
}
