import HealthAnalysisCore
import Testing

@MainActor @Test func newApplicationHasNoDataOrAnalyses() {
    let overview = HealthAnalysisApplication().overview

    #expect(!overview.hasReadableMeasurements)
    #expect(!overview.hasTrackingVariables)
    #expect(!overview.hasFollowedAnalyses)
    #expect(!overview.hasDiscoveries)
}
