import Foundation
import HealthAnalysisCore
import HealthKit

enum HealthKitHRVStream {
    private static let rmssd: HKQuantityType? = {
        guard #available(iOS 27.0, *) else { return nil }
        // The runtime lookup keeps the app buildable with the iOS 26 SDK.
        return HKObjectType.quantityType(forIdentifier: .init(rawValue: HRVSeries.StoredType.rmssd.rawValue))
    }()

    private static let types = [HKQuantityType(.heartRateVariabilitySDNN)] + [rmssd].compactMap { $0 }

    static var supportsRMSSD: Bool { rmssd != nil }
    static let queries = types.map { type in
        HealthKitMeasurementQuery(type: type, predicate: .quantitySample(type: type), measurement: measurement)
    }

    private static func measurement(from sample: HKQuantitySample) -> HealthMeasurement {
        let revision = sample.sourceRevision
        let os = revision.operatingSystemVersion
        let metadata = sample.metadata
        return HealthMeasurement(
            id: sample.uuid,
            metric: .init(rawValue: sample.quantityType.identifier),
            value: sample.quantity.doubleValue(for: .secondUnit(with: .milli)),
            unit: .milliseconds,
            startDate: sample.startDate,
            endDate: sample.endDate,
            source: .init(name: revision.source.name, bundleIdentifier: revision.source.bundleIdentifier),
            timeZoneIdentifier: metadata?[HKMetadataKeyTimeZone] as? String,
            sourceRevision: .init(
                version: revision.version,
                productType: revision.productType,
                operatingSystemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            ),
            hrvProvenance: .init(
                quantityCount: sample.count,
                syncIdentifier: metadata?[HKMetadataKeySyncIdentifier] as? String,
                syncVersion: (metadata?[HKMetadataKeySyncVersion] as? NSNumber).flatMap { version in
                    let integer = version.intValue
                    return version == NSNumber(value: integer) ? integer : nil
                },
                deviceManufacturer: sample.device?.manufacturer,
                deviceModel: sample.device?.model
            )
        )
    }
}
