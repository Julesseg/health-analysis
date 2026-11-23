import Foundation
import Observation

@MainActor
@Observable
public final class DiscoveryActivity {
    public fileprivate(set) var report: DiscoveryReport?
    public fileprivate(set) var unavailableStatus: DiscoveryReport.Status?
    public var isSearching: Bool { requestID != nil }

    fileprivate var requestID: UUID?
    @ObservationIgnored fileprivate var enabledSeries: Set<AnalysisSeriesID>?
    @ObservationIgnored fileprivate var timeZone: TimeZone?
    @ObservationIgnored fileprivate var lastSearchStartedAt: Date?

    nonisolated init() {}
}

extension HealthAnalysisApplication {
    @MainActor func refreshDiscoveriesIfNeeded(
        asOf cutoff: Date, timeZone: TimeZone, enabledSeries: Set<AnalysisSeriesID>?
    ) async {
        let scope = enabledSeries ?? Set(discoverySeries)
        if healthMeasurements.readState == .loaded,
           scope == discovery.enabledSeries, timeZone == discovery.timeZone,
           discovery.unavailableStatus == nil, let started = discovery.lastSearchStartedAt,
           let report = discovery.report, timeZoneCalendar(timeZone).isDate(report.cutoff, inSameDayAs: cutoff),
           !scope.contains(where: { series in
               guard case .health(let metric, _) = series else { return false }
               return [series, .health(metric: metric)].contains {
                   healthMeasurements.analysisChangeDate(for: $0).map { $0 > started } ?? false
               }
           }) {
            return
        }
        await refreshDiscoveries(asOf: cutoff, timeZone: timeZone, enabledSeries: scope)
    }

    private func timeZoneCalendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    @MainActor public func refreshDiscoveries(
        asOf cutoff: Date = .now, timeZone: TimeZone = .current, enabledSeries: Set<AnalysisSeriesID>? = nil
    ) async {
        guard !Task.isCancelled else { return }
        let scope = enabledSeries ?? Set(discoverySeries)
        if scope != discovery.enabledSeries || timeZone != discovery.timeZone {
            discovery.report = nil
            discovery.unavailableStatus = nil
            discovery.enabledSeries = scope
            discovery.timeZone = timeZone
        }

        let requestID = UUID()
        let started = Date.now
        let reconciliation = healthMeasurements.reconciliationVersion
        let read = healthMeasurements.readState
        let logRevision = manualLog.analysisRevision
        discovery.requestID = requestID
        let report = await discover(asOf: cutoff, timeZone: timeZone, enabledSeries: scope)
        guard discovery.requestID == requestID else { return }
        discovery.requestID = nil
        guard !Task.isCancelled, let report, healthMeasurements.reconciliationVersion == reconciliation,
              healthMeasurements.readState == read, manualLog.analysisRevision == logRevision else { return }

        switch report.status {
        case .manualLogUnavailable, .healthHistoryUnavailable, .healthHistoryLoading:
            discovery.unavailableStatus = report.status
        default:
            discovery.report = report
            discovery.unavailableStatus = nil
            discovery.lastSearchStartedAt = started
        }
    }
}
