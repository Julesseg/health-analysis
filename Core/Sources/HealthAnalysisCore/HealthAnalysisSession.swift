import Foundation

public struct HealthAnalysisSession {
    public enum Tab: Hashable {
        case insights, explore, data
    }

    public enum Sheet: Hashable, Identifiable {
        case log, settings

        public var id: Self { self }
    }

    public struct LibrarySummary {
        public let measurements: Int
        public let trackingVariables: Int
        public let savedAnalyses: Int
        public let discoveries: Int

        public var canExplore: Bool { measurements > 0 || trackingVariables > 0 }
    }

    public let library = LibrarySummary(measurements: 0, trackingVariables: 0, savedAnalyses: 0, discoveries: 0)
    public var tab: Tab = .insights
    public var sheet: Sheet?
    public var logDate: Date

    public init(today: Date = .now) {
        logDate = today
    }

    public mutating func openLog(today: Date = .now) {
        logDate = today
        sheet = .log
    }
}
