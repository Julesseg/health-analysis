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

    fileprivate var searchedLogRevision: Int?
    fileprivate var searchedHealthVersion: Int?
    public private(set) var disabledSeries: Set<AnalysisSeriesID>
    private let preferencesKey: String?

    nonisolated init(preferencesKey: String?) {
        self.preferencesKey = preferencesKey
        let stored = preferencesKey.flatMap { UserDefaults.standard.data(forKey: $0) }
        _disabledSeries = stored.flatMap { try? JSONDecoder().decode(Set<AnalysisSeriesID>.self, from: $0) } ?? []
    }

    public func setEnabled(_ enabled: Bool, for series: AnalysisSeriesID) {
        if enabled {
            disabledSeries.remove(series)
        } else {
            disabledSeries.insert(series)
        }
        if let preferencesKey, let data = try? JSONEncoder().encode(disabledSeries) {
            UserDefaults.standard.set(data, forKey: preferencesKey)
        }
    }
}

extension HealthAnalysisApplication {
    public struct DiscoveryRequest: Equatable, Sendable {
        let enabledSeries: Set<AnalysisSeriesID>
        let logRevision: Int
        let healthRevision: Int
    }

    @MainActor public var discoveryRequest: DiscoveryRequest {
        .init(
            enabledSeries: Set(discoverySeries).subtracting(discovery.disabledSeries),
            logRevision: manualLog.analysisRevision, healthRevision: healthMeasurements.reconciliationVersion
        )
    }

    @MainActor public var discoveryIsStale: Bool {
        discovery.report != nil && (
            discovery.searchedLogRevision != manualLog.analysisRevision
                || discovery.searchedHealthVersion != healthMeasurements.reconciliationVersion
                || discovery.enabledSeries != discoveryRequest.enabledSeries
        )
    }

    @MainActor func refreshDiscoveriesIfNeeded(
        asOf cutoff: Date, timeZone: TimeZone, enabledSeries: Set<AnalysisSeriesID>?
    ) async {
        let scope = enabledSeries ?? discoveryRequest.enabledSeries
        if healthMeasurements.readState == .loaded,
           scope == discovery.enabledSeries, timeZone == discovery.timeZone,
           discovery.searchedLogRevision == manualLog.analysisRevision,
           discovery.unavailableStatus == nil, let started = discovery.lastSearchStartedAt,
           let report = discovery.report, timeZoneCalendar(timeZone).isDate(report.cutoff, inSameDayAs: cutoff),
           !scope.contains(where: { series in
               guard case .health(let metric, _) = series else { return false }
               return [series, .health(metric: metric)].contains {
                   healthMeasurements.analysisChangeDate(for: $0).map { $0 > started } ?? false
               }
           }) {
            discovery.searchedHealthVersion = healthMeasurements.reconciliationVersion
            return
        }
        await refreshDiscoveries(asOf: cutoff, timeZone: timeZone, enabledSeries: enabledSeries)
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
        let requestID = UUID()
        let started = Date.now
        let reconciliation = healthMeasurements.reconciliationVersion
        let read = healthMeasurements.readState
        discovery.requestID = requestID
        defer {
            if discovery.requestID == requestID { discovery.requestID = nil }
        }
        while !Task.isCancelled, discovery.requestID == requestID {
            let logRevision = manualLog.analysisRevision
            let scope = enabledSeries ?? discoveryRequest.enabledSeries
            if scope != discovery.enabledSeries || timeZone != discovery.timeZone {
                discovery.report = nil
                discovery.unavailableStatus = nil
                discovery.enabledSeries = scope
                discovery.timeZone = timeZone
            }
            let report = await discover(asOf: cutoff, timeZone: timeZone, enabledSeries: scope)
            guard discovery.requestID == requestID, !Task.isCancelled, let report,
                  healthMeasurements.reconciliationVersion == reconciliation, healthMeasurements.readState == read
            else { return }
            if manualLog.analysisRevision != logRevision || (enabledSeries == nil && discoveryRequest.enabledSeries != scope) {
                continue
            }

            switch report.status {
            case .manualLogUnavailable, .healthHistoryUnavailable, .healthHistoryLoading:
                discovery.unavailableStatus = report.status
            default:
                discovery.report = report
                discovery.unavailableStatus = nil
                discovery.lastSearchStartedAt = started
                discovery.searchedLogRevision = logRevision
                discovery.searchedHealthVersion = reconciliation
            }
            return
        }
    }
}
