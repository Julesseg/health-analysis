import Foundation

public struct DiscoverySelection: Codable, Sendable {
    public enum Contrast: Codable, Hashable, Sendable {
        case input(AnalysisSeriesID)
        case interaction(AnalysisInteraction)
    }

    public let methodVersion: Int
    public let cutoff: Date
    public let contrast: Contrast
    public let familySize: Int
    public let adjustedPValue: Double
}

public struct DiscoveryFinding: Identifiable, Sendable {
    public var id: AnalysisConfiguration { configuration }
    public var configuration: AnalysisConfiguration { completed.result.configuration }
    public let completed: CompletedAnalysis
}

public struct DiscoveryCandidate: Sendable {
    public enum Outcome: Sendable {
        case modelInsufficient([AnalysisEvidence.Reason])
        case insufficientBlockEvidence
        case tested(adjustedPValue: Double)
    }

    public let configuration: AnalysisConfiguration
    public let contrast: DiscoverySelection.Contrast
    public let outcome: Outcome
}

public struct DiscoveryReport: Sendable {
    public enum Status: Equatable, Sendable {
        case noEnabledInputs
        case noEnabledOutputs
        case noReadableOutputs
        case chooseOutputSource
        case manualLogUnavailable
        case healthHistoryUnavailable(HealthMeasurementReadFailure)
        case healthHistoryLoading
        case insufficientModelEvidence
        case insufficientBlockEvidence
        case noFindings
        case findings
    }

    public let cutoff: Date
    public let status: Status
    public let candidates: [DiscoveryCandidate]
    public let findings: [DiscoveryFinding]
    public let omittedInputCount: Int
}

extension HealthAnalysisApplication {
    public static let discoveryOutputMetrics: [HealthMeasurement.Metric] = [.restingHeartRate, .sleepAnalysis]

    @MainActor public var discoverySeries: [AnalysisSeriesID] {
        analysisVariables.filter { variable in
            switch variable.id {
            case .manualQuantity: variable.supportsInput
            case .health(let metric, _): Self.discoveryOutputMetrics.contains(metric) && variable.supportsOutput
            case .manualTyped: false
            }
        }.map(\.id)
    }

    @MainActor public func discover(
        asOf cutoff: Date = .now, timeZone: TimeZone = .current, enabledSeries: Set<AnalysisSeriesID>? = nil
    ) async -> DiscoveryReport? {
        guard !Task.isCancelled else { return nil }
        func empty(_ status: DiscoveryReport.Status, omittedInputs: Int = 0) -> DiscoveryReport {
            DiscoveryReport(
                cutoff: cutoff, status: status, candidates: [], findings: [], omittedInputCount: omittedInputs
            )
        }

        guard manualLog.isStoreAvailable else { return empty(.manualLogUnavailable) }
        let enabled = enabledSeries ?? Set(discoverySeries)
        let availableInputs = manualAnalysisSeries.filter { series in
            let variable = series.variable
            if case .manualQuantity = variable.id { return variable.supportsInput && enabled.contains(variable.id) }
            return false
        }
        guard !availableInputs.isEmpty else { return empty(.noEnabledInputs) }
        let inputs = Array(availableInputs.prefix(DiscoverySearch.maximumInputs))
        let omittedInputCount = availableInputs.count - inputs.count

        let enabledMetrics = Set(enabled.compactMap { series -> HealthMeasurement.Metric? in
            if case .health(let metric, _) = series { return metric }
            return nil
        })
        let metrics = Self.discoveryOutputMetrics.filter { enabledMetrics.contains($0) }
        guard !metrics.isEmpty else { return empty(.noEnabledOutputs, omittedInputs: omittedInputCount) }
        switch healthMeasurements.readState {
        case .failed(let failure):
            return empty(.healthHistoryUnavailable(failure), omittedInputs: omittedInputCount)
        case .loading:
            return empty(.healthHistoryLoading, omittedInputs: omittedInputCount)
        case .idle, .loaded:
            break
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let historyEnd = calendar.startOfDay(for: cutoff)
        guard let startOfHistory = calendar.day(byGoingBack: DiscoverySearch.historyDays - 1, from: historyEnd) else {
            return empty(.noReadableOutputs, omittedInputs: omittedInputCount)
        }
        var plans: [DiscoverySearch.OutputPlan] = []
        var ambiguousSource = false
        for metric in metrics {
            let usesPreferredSource = enabled.contains(.health(metric: metric))
            let outputs = availableHealthOutputs(metric, asOf: cutoff, calendar: calendar).filter { output in
                guard (startOfHistory...historyEnd).contains(output.date),
                      let sourceID = output.source?.bundleIdentifier else { return false }
                return usesPreferredSource || enabled.contains(.health(metric: metric, sourceBundleIdentifier: sourceID))
            }
            let sources = Set(outputs.compactMap { $0.source?.bundleIdentifier })
            guard !sources.isEmpty else { continue }
            let preferred = healthMeasurements.preferredSource(for: metric)?.bundleIdentifier
            let sourceID: String?
            if let preferred, usesPreferredSource {
                sourceID = sources.contains(preferred) ? preferred : nil
            } else if let preferred, sources.contains(preferred) {
                sourceID = preferred
            } else {
                sourceID = sources.count == 1 ? sources.first : nil
                ambiguousSource = ambiguousSource || sources.count > 1
            }
            guard let sourceID else { continue }
            let selectedOutputs = outputs.filter { $0.source?.bundleIdentifier == sourceID }
            for window in AnalysisBehaviorWindow.allCases {
                plans.append(DiscoverySearch.OutputPlan(
                    output: .health(metric: metric, sourceBundleIdentifier: sourceID), metric: metric, window: window,
                    plan: .init(outputs: selectedOutputs, window: window, history: .last365Days, asOf: cutoff, calendar: calendar)
                ))
            }
        }
        guard !plans.isEmpty else {
            return empty(ambiguousSource ? .chooseOutputSource : .noReadableOutputs, omittedInputs: omittedInputCount)
        }

        let dates = Set(plans.flatMap { $0.plan.rows.flatMap(\.behaviorDates) })
        let dailyInputs = Dictionary(uniqueKeysWithValues: inputs.map { series in
            let values = dates.compactMap { date in
                TemporalAnalysisDataset.inputDay(date, for: series, manualLog: manualLog, timeZone: timeZone)
            }
            return (series.variable.id, Dictionary(uniqueKeysWithValues: values.map { ($0.date, $0) }))
        })
        let search = DiscoverySearch(
            cutoff: cutoff, calendar: calendar, startOfHistory: startOfHistory, inputs: inputs.map(\.variable),
            plans: plans, dailyInputs: dailyInputs, lastReadAt: healthMeasurements.lastSuccessfulReadAt,
            omittedInputCount: omittedInputCount
        )
        let work = Task.detached(priority: .utility) { search.evaluate() }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }
}
