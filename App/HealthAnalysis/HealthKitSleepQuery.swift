import HealthAnalysisCore
import HealthKit

extension HealthKitMeasurementQuery {
    static let sleep: Self = {
        let type = HKCategoryType(.sleepAnalysis)
        return Self(type: type, predicate: .categorySample(type: type)) { sample in
            let revision = sample.sourceRevision
            let source = revision.source
            let os = revision.operatingSystemVersion
            return HealthMeasurement(
                id: sample.uuid,
                sleepStage: SleepStage(rawValue: sample.value),
                startDate: sample.startDate,
                endDate: sample.endDate,
                source: .init(name: source.name, bundleIdentifier: source.bundleIdentifier),
                timeZoneIdentifier: sample.metadata?[HKMetadataKeyTimeZone] as? String,
                sourceRevision: .init(
                    version: revision.version,
                    productType: revision.productType,
                    operatingSystemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
                )
            )
        }
    }()
}
