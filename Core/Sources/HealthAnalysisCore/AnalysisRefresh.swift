import Foundation

public struct CompletedAnalysis: Codable, Sendable {
    public let result: AnalysisResult
    public let updatedAt: Date
    public let discovery: DiscoverySelection?

    init(result: AnalysisResult, updatedAt: Date, discovery: DiscoverySelection? = nil) {
        self.result = result
        self.updatedAt = updatedAt
        self.discovery = discovery
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

actor AnalysisFitter {
    func assess(_ analysis: @escaping PreparedAnalysis) -> AnalysisResult? {
        guard !Task.isCancelled else { return nil }
        return analysis()
    }
}

extension HealthAnalysisApplication {
    @MainActor
    public func refreshAnalysis(
        _ configuration: AnalysisConfiguration
    ) async -> Result<CompletedAnalysis, AnalysisRunFailure>? {
        guard !Task.isCancelled else { return nil }
        if case .manualTyped = configuration.output {
            return analyzeForRefresh(configuration, asOf: .now)
        }
        guard let read = await healthMeasurements.refreshForAnalysis(), !Task.isCancelled else { return nil }
        guard healthMeasurements.readState == read else { return nil }
        return analyzeReconciled(configuration, read: read, asOf: .now)
    }

    @MainActor private func analyzeReconciled(
        _ configuration: AnalysisConfiguration, read: HealthMeasurementHistory.ReadState, asOf: Date
    ) -> Result<CompletedAnalysis, AnalysisRunFailure> {
        switch read {
        case .failed(let failure):
            return .failure(.healthHistoryUnavailable(failure))
        case .idle:
            return .failure(.healthHistoryUnavailable(.unavailable))
        case .loading:
            return .failure(.healthHistoryLoading)
        case .loaded:
            return analyzeForRefresh(configuration, asOf: asOf)
        }
    }

    @MainActor private func analyzeForRefresh(
        _ configuration: AnalysisConfiguration, asOf: Date
    ) -> Result<CompletedAnalysis, AnalysisRunFailure> {
        do {
            return completedRefresh(from: try analyze(configuration, asOf: asOf))
        } catch {
            return .failure(error)
        }
    }

    @MainActor
    public func refreshSavedAnalysis(_ id: SavedAnalysis.ID) async {
        guard let question = savedAnalyses.question(id: id) else { return }
        let requestID = savedAnalyses.beginRefresh(for: id)
        let result = await refreshAnalysis(question.configuration)
        savedAnalyses.finishRefresh(for: id, requestID: requestID, result: result)
    }

    @MainActor public func refreshReconciledHealthInsights(
        asOf cutoff: Date = .now, timeZone: TimeZone = .current, enabledSeries: Set<AnalysisSeriesID>? = nil
    ) async {
        let read = healthMeasurements.readState
        guard read != .loading, !Task.isCancelled else { return }
        let version = healthMeasurements.reconciliationVersion
        if read != .idle {
            savedAnalyses.reloadIfUnavailable()
            for question in savedAnalyses.following {
                guard !Task.isCancelled, healthMeasurements.reconciliationVersion == version,
                      healthMeasurements.readState == read else { return }
                guard let output = question.configuration.output.healthHistorySeries,
                      savedAnalyses.isPinned(question.id),
                      savedAnalyses.question(id: question.id)?.configuration == question.configuration else { continue }
                let state = savedAnalyses.state(for: question.id)
                if read == .loaded {
                    if let completed = state.completed, state.failure == nil,
                       !(healthMeasurements.analysisChangeDate(for: output).map { $0 > completed.updatedAt } ?? false) {
                        continue
                    }
                }
                guard let requestID = savedAnalyses.beginAutomaticRefresh(for: question.id) else { continue }
                let result: Result<CompletedAnalysis, AnalysisRunFailure>?
                if read == .loaded {
                    result = await fitReconciled(question.configuration, version: version, asOf: cutoff)
                } else {
                    result = analyzeReconciled(question.configuration, read: read, asOf: cutoff)
                }
                savedAnalyses.finishRefresh(
                    for: question.id, requestID: requestID, result: savedAnalyses.isPinned(question.id) ? result : nil
                )
            }
        }
        guard healthMeasurements.reconciliationVersion == version, healthMeasurements.readState == read else { return }
        await refreshDiscoveriesIfNeeded(asOf: cutoff, timeZone: timeZone, enabledSeries: enabledSeries)
    }

    @MainActor private func fitReconciled(
        _ configuration: AnalysisConfiguration, version: Int, asOf: Date
    ) async -> Result<CompletedAnalysis, AnalysisRunFailure>? {
        let logRevision = manualLog.analysisRevision
        do {
            let prepared = try prepareAnalysis(configuration, asOf: asOf)
            guard let result = await analysisFitter.assess(prepared), !Task.isCancelled,
                  healthMeasurements.reconciliationVersion == version, healthMeasurements.readState == .loaded,
                  manualLog.analysisRevision == logRevision else { return nil }
            return completedRefresh(from: result)
        } catch {
            return .failure(error)
        }
    }

    private func completedRefresh(from result: AnalysisResult) -> Result<CompletedAnalysis, AnalysisRunFailure> {
        if let failure = result.lastHealthReadFailure { return .failure(.healthHistoryUnavailable(failure)) }
        return .success(CompletedAnalysis(result: result, updatedAt: .now))
    }
}

private extension AnalysisSeriesID {
    var healthHistorySeries: AnalysisSeriesID? {
        switch self {
        case .health: self
        case .sleepTiming(_, let source): .health(metric: .sleepAnalysis, sourceBundleIdentifier: source)
        case .manualQuantity, .manualTyped: nil
        }
    }
}
