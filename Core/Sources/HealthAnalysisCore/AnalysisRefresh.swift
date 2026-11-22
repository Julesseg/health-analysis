import Foundation

public struct CompletedAnalysis: Codable, Sendable {
    public let result: AnalysisResult
    public let updatedAt: Date
    public let discovery: DiscoverySelection?
    public let reassessment: DiscoveryReassessment?

    init(
        result: AnalysisResult, updatedAt: Date, discovery: DiscoverySelection? = nil,
        reassessment: DiscoveryReassessment? = nil
    ) {
        self.result = result
        self.updatedAt = updatedAt
        self.discovery = discovery
        self.reassessment = reassessment
    }
}

public enum AnalysisRefreshFailure: Equatable, Sendable {
    case analysis(AnalysisRunFailure)
    case persistence
}

public struct AnalysisRefreshState: Sendable {
    public let completed: CompletedAnalysis?
    public let isRefreshing: Bool
    public let failure: AnalysisRefreshFailure?

    public init(
        completed: CompletedAnalysis? = nil,
        isRefreshing: Bool = false,
        failure: AnalysisRefreshFailure? = nil
    ) {
        self.completed = completed
        self.isRefreshing = isRefreshing
        self.failure = failure
    }
}

extension HealthAnalysisApplication {
    @MainActor
    public func refreshAnalysis(
        _ configuration: AnalysisConfiguration
    ) async -> Result<CompletedAnalysis, AnalysisRunFailure>? {
        await refreshAnalysis(configuration, asOf: nil, discoveryBaseline: nil)
    }

    @MainActor
    private func refreshAnalysis(
        _ configuration: AnalysisConfiguration, asOf: Date?, discoveryBaseline: CompletedAnalysis?
    ) async -> Result<CompletedAnalysis, AnalysisRunFailure>? {
        guard !Task.isCancelled else { return nil }
        if case .manualTyped = configuration.output {
            return completeAnalysis(usingReconciledHistory: configuration, asOf: asOf ?? .now)
        }
        guard let read = await healthMeasurements.refreshForAnalysis(), !Task.isCancelled else { return nil }

        switch read {
        case .failed(let failure):
            return .failure(.healthHistoryUnavailable(failure))
        case .idle:
            return .failure(.healthHistoryUnavailable(.unavailable))
        case .loading:
            return .failure(.healthHistoryLoading)
        case .loaded:
            return completeAnalysis(
                usingReconciledHistory: configuration, asOf: asOf ?? .now, discoveryBaseline: discoveryBaseline
            )
        }
    }

    @MainActor
    func completeAnalysis(
        usingReconciledHistory configuration: AnalysisConfiguration, asOf: Date,
        discoveryBaseline: CompletedAnalysis? = nil
    ) -> Result<CompletedAnalysis, AnalysisRunFailure> {
        do {
            let result = try analyze(configuration, asOf: asOf)
            if let failure = result.lastHealthReadFailure {
                return .failure(.healthHistoryUnavailable(failure))
            }
            let reassessment: DiscoveryReassessment?
            if let baseline = discoveryBaseline, let selection = baseline.discovery,
               baseline.result.configuration == configuration {
                let later = try analyze(
                    configuration, asOf: asOf, after: selection.cutoff,
                    interactionReference: baseline.result.interaction
                )
                reassessment = later.model == baseline.result.model
                    ? DiscoveryReassessment(result: later, original: baseline.result, contrast: selection.contrast)
                    : nil
            } else {
                reassessment = nil
            }
            return .success(CompletedAnalysis(result: result, updatedAt: .now, reassessment: reassessment))
        } catch {
            return .failure(error)
        }
    }

    @MainActor
    public func refreshSavedAnalysis(_ id: SavedAnalysis.ID, asOf: Date? = nil) async {
        guard let question = savedAnalyses.question(id: id) else { return }
        let requestID = savedAnalyses.beginRefresh(for: id)
        let baseline = savedAnalyses.discoveryBaseline(for: id)
        let result = await refreshAnalysis(question.configuration, asOf: asOf, discoveryBaseline: baseline)
        savedAnalyses.finishRefresh(for: id, requestID: requestID, result: result)
    }
}
