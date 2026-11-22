import Foundation

extension HealthMeasurement.Metric {
    public static let sleepAnalysis = Self(rawValue: "sleepAnalysis")
}

public struct SleepStage: RawRepresentable, Hashable, Sendable {
    public static let inBed = Self(rawValue: 0)
    public static let asleepUnspecified = Self(rawValue: 1)
    public static let awake = Self(rawValue: 2)
    public static let asleepCore = Self(rawValue: 3)
    public static let asleepDeep = Self(rawValue: 4)
    public static let asleepREM = Self(rawValue: 5)

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
        default: false
        }
    }
}

extension HealthMeasurement {
    public init(
        id: UUID,
        sleepStage: SleepStage,
        startDate: Date,
        endDate: Date,
        source: Source,
        timeZoneIdentifier: String? = nil,
        sourceRevision: SourceRevision? = nil
    ) {
        self.init(
            id: id, metric: .sleepAnalysis, value: Double(sleepStage.rawValue), unit: .sleepStage,
            startDate: startDate, endDate: endDate, source: source,
            timeZoneIdentifier: timeZoneIdentifier, sourceRevision: sourceRevision
        )
    }

    public var sleepStage: SleepStage? {
        guard metric == .sleepAnalysis, unit == .sleepStage, let raw = Int(exactly: value) else { return nil }
        return SleepStage(rawValue: raw)
    }
}

public enum SleepTiming: String, CaseIterable, Codable, Hashable, Sendable {
    case onset
    case wake
}

public struct SleepEpisode: Equatable, Identifiable, Sendable {
    public struct ID: Hashable, Sendable {
        public let sourceIdentifier: String
        public let startDate: Date
    }

    public enum TimeZoneEvidence: Codable, Equatable, Sendable {
        case sampleMetadata(identifier: String, sampleID: UUID)
        case importTimeZone(identifier: String)

        public var identifier: String {
            switch self {
            case .sampleMetadata(let identifier, _), .importTimeZone(let identifier): identifier
            }
        }
    }

    public var id: ID { ID(sourceIdentifier: source.bundleIdentifier, startDate: startDate) }
    public let source: HealthMeasurement.Source
    public let startDate: Date
    public let wakeTime: Date
    public let duration: TimeInterval
    public let timeZoneEvidence: TimeZoneEvidence
    public let onsetTimeZoneEvidence: TimeZoneEvidence

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneEvidence.identifier) ?? .gmt }

    public var wakeDay: DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day], from: wakeTime)
    }
}
