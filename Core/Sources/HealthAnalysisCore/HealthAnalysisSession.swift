import Foundation

public struct HealthAnalysisSession {
    public enum Tab: Hashable {
        case analysis, log
    }

    public private(set) var tab: Tab = .analysis
    public var logDate: Date

    public init(today: Date = .now) {
        logDate = today
    }

    public mutating func selectTab(_ tab: Tab, today: Date = .now) {
        if self.tab != tab && tab == .log {
            logDate = today
        }
        self.tab = tab
    }
}
