import Foundation

public struct CompletedAnalysis: Codable, Sendable {
    public let result: AnalysisResult
    public let updatedAt: Date
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
        guard !Task.isCancelled else { return nil }
        guard let read = await healthMeasurements.refreshForAnalysis(), !Task.isCancelled else { return nil }

        switch read {
        case .failed(let failure):
            return .failure(.healthHistoryUnavailable(failure))
        case .idle:
            return .failure(.healthHistoryUnavailable(.unavailable))
        case .loading:
            return .failure(.healthHistoryLoading)
        case .loaded:
            do {
                let result = try analyze(configuration)
                if let failure = result.lastHealthReadFailure {
                    return .failure(.healthHistoryUnavailable(failure))
                }
                return .success(CompletedAnalysis(result: result, updatedAt: .now))
            } catch {
                return .failure(error)
            }
        }
    }

    @MainActor
    public func refreshSavedAnalysis(_ id: SavedAnalysis.ID) async {
        guard let question = savedAnalyses.question(id: id) else { return }
        let requestID = savedAnalyses.beginRefresh(for: id)
        let result = await refreshAnalysis(question.configuration)
        savedAnalyses.finishRefresh(for: id, requestID: requestID, result: result)
    }
}
