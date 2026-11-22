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

    nonisolated init() {}
}

extension HealthAnalysisApplication {
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
        discovery.requestID = requestID
        let report = await discover(asOf: cutoff, timeZone: timeZone, enabledSeries: scope)
        guard discovery.requestID == requestID else { return }
        discovery.requestID = nil
        guard !Task.isCancelled, let report else { return }

        switch report.status {
        case .manualLogUnavailable, .healthHistoryUnavailable, .healthHistoryLoading:
            discovery.unavailableStatus = report.status
        default:
            discovery.report = report
            discovery.unavailableStatus = nil
        }
    }
}
