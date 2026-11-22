import HealthAnalysisCore
import Testing

@Test func newApplicationHasNoDataOrAnalyses() {
    let overview = HealthAnalysisApplication().overview

    #expect(!overview.hasReadableMeasurements)
    #expect(!overview.hasTrackingVariables)
    #expect(!overview.hasFollowedAnalyses)
    #expect(!overview.hasDiscoveries)
}
