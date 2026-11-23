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

typealias PreparedAnalysisRefresh = @Sendable () -> Result<CompletedAnalysis, AnalysisRunFailure>

actor AnalysisFitter {
    func complete(_ refresh: @escaping PreparedAnalysisRefresh) -> Result<CompletedAnalysis, AnalysisRunFailure>? {
        guard !Task.isCancelled else { return nil }
        return refresh()
    }
}

extension HealthAnalysisApplication {
    @MainActor
    public func refreshAnalysis(
        _ configuration: AnalysisConfiguration
    ) async -> Result<CompletedAnalysis, AnalysisRunFailure>? {
        await refreshAnalysis(configuration, asOf: nil, discoveryBaseline: nil)
    }

    @MainActor private func refreshAnalysis(
        _ configuration: AnalysisConfiguration, asOf: Date?, discoveryBaseline: CompletedAnalysis?
    ) async -> Result<CompletedAnalysis, AnalysisRunFailure>? {
        guard !Task.isCancelled else { return nil }
        if case .manualTyped = configuration.output {
            return completeAnalysis(usingReconciledHistory: configuration, asOf: asOf ?? .now)
        }
        guard let read = await healthMeasurements.refreshForAnalysis(), !Task.isCancelled,
              healthMeasurements.readState == read else { return nil }
        if let failure = read.analysisFailure { return .failure(failure) }
        return completeAnalysis(
            usingReconciledHistory: configuration, asOf: asOf ?? .now, discoveryBaseline: discoveryBaseline
        )
    }

    @MainActor private func completeAnalysis(
        usingReconciledHistory configuration: AnalysisConfiguration, asOf: Date,
        discoveryBaseline: CompletedAnalysis? = nil
    ) -> Result<CompletedAnalysis, AnalysisRunFailure> {
        do {
            return try prepareRefresh(configuration, asOf: asOf, discoveryBaseline: discoveryBaseline)()
        } catch {
            return .failure(error)
        }
    }

    @MainActor private func prepareRefresh(
        _ configuration: AnalysisConfiguration, asOf: Date, discoveryBaseline: CompletedAnalysis?
    ) throws(AnalysisRunFailure) -> PreparedAnalysisRefresh {
        let ordinary = try prepareAnalysis(configuration, asOf: asOf)
        let laterEvidence: (original: AnalysisResult, contrast: DiscoverySelection.Contrast, assess: PreparedAnalysis)?
        if let baseline = discoveryBaseline, let selection = baseline.discovery,
           baseline.result.configuration == configuration {
            laterEvidence = (
                baseline.result, selection.contrast,
                try prepareAnalysis(
                    configuration, asOf: asOf, after: selection.cutoff,
                    interactionReference: baseline.result.interaction
                )
            )
        } else {
            laterEvidence = nil
        }

        return {
            let result = ordinary()
            if let failure = result.lastHealthReadFailure { return .failure(.healthHistoryUnavailable(failure)) }
            let reassessment = laterEvidence.flatMap { evidence -> DiscoveryReassessment? in
                let later = evidence.assess()
                guard later.model == evidence.original.model else { return nil }
                return DiscoveryReassessment(result: later, original: evidence.original, contrast: evidence.contrast)
            }
            return .success(CompletedAnalysis(result: result, updatedAt: .now, reassessment: reassessment))
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
                if read == .loaded, let completed = state.completed, state.failure == nil {
                    let checkedAt = completed.discovery == nil
                        ? completed.updatedAt
                        : completed.result.healthHistoryReadAt ?? completed.updatedAt
                    if !(healthMeasurements.analysisChangeDate(for: output).map { $0 > checkedAt } ?? false) {
                        continue
                    }
                }
                guard let requestID = savedAnalyses.beginAutomaticRefresh(for: question.id) else { continue }
                let result: Result<CompletedAnalysis, AnalysisRunFailure>?
                if let failure = read.analysisFailure {
                    result = .failure(failure)
                } else {
                    result = await fitReconciled(question, version: version, asOf: cutoff)
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
        _ question: SavedAnalysis, version: Int, asOf: Date
    ) async -> Result<CompletedAnalysis, AnalysisRunFailure>? {
        let logRevision = manualLog.analysisRevision
        do {
            let prepared = try prepareRefresh(
                question.configuration, asOf: asOf, discoveryBaseline: savedAnalyses.discoveryBaseline(for: question.id)
            )
            let result = await analysisFitter.complete(prepared)
            guard !Task.isCancelled, healthMeasurements.reconciliationVersion == version,
                  healthMeasurements.readState == .loaded, manualLog.analysisRevision == logRevision else { return nil }
            return result
        } catch {
            return .failure(error)
        }
    }
}

private extension HealthMeasurementHistory.ReadState {
    var analysisFailure: AnalysisRunFailure? {
        switch self {
        case .failed(let failure): .healthHistoryUnavailable(failure)
        case .idle: .healthHistoryUnavailable(.unavailable)
        case .loading: .healthHistoryLoading
        case .loaded: nil
        }
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
