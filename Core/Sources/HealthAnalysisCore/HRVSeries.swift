import Foundation

extension HealthMeasurement {
    public struct HRVProvenance: Codable, Equatable, Sendable {
        public let quantityCount: Int
        public let syncIdentifier: String?
        public let syncVersion: Int?
        public let deviceManufacturer: String?
        public let deviceModel: String?

        public init(
            quantityCount: Int, syncIdentifier: String?, syncVersion: Int?,
            deviceManufacturer: String? = nil, deviceModel: String? = nil
        ) {
            self.quantityCount = quantityCount
            self.syncIdentifier = syncIdentifier
            self.syncVersion = syncVersion
            self.deviceManufacturer = deviceManufacturer
            self.deviceModel = deviceModel
        }
    }
}

public struct HRVSeries: Sendable {
    public enum StoredType: String, CaseIterable, Sendable {
        case sdnn = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        case rmssd = "HKQuantityTypeIdentifierHeartRateVariabilityRMSSD"

        public var metric: HealthMeasurement.Metric { .init(rawValue: rawValue) }
    }

    public enum AnalysisLimitation: Sendable {
        case unverifiedOriginalMeasureAndSummary
    }

    public let storedType: StoredType
    public let source: HealthMeasurement.Source
    public let coverage: HealthMeasurementHistory.Coverage
    public let records: [HealthMeasurement]

    public var analysisLimitation: AnalysisLimitation { .unverifiedOriginalMeasureAndSummary }
}

extension HealthMeasurementHistory {
    public func hrvSeries(for storedType: HRVSeries.StoredType, calendar: Calendar = .current) -> [HRVSeries] {
        let records = history.filter { $0.metric == storedType.metric }
        let bySource = Dictionary(grouping: records) { $0.source.bundleIdentifier }
        return bySource.values.compactMap { records in
            guard let latest = records.first, let coverage = Self.sampleCoverage(records: records, calendar: calendar) else {
                return nil
            }
            return HRVSeries(storedType: storedType, source: latest.source, coverage: coverage, records: records)
        }.sorted {
            ($0.source.name, $0.source.bundleIdentifier) < ($1.source.name, $1.source.bundleIdentifier)
        }
    }
}
