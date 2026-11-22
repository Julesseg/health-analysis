import HealthAnalysisCore
import HealthKit

struct HealthKitMeasurementSource: HealthMeasurementSource {
    private let store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    private static let restingHeartRate = HKQuantityType(.restingHeartRate)

    func requestReadAccess() async throws {
        guard let store else { throw HealthMeasurementReadFailure.unavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: [Self.restingHeartRate])
        } catch {
            throw availabilityFailure(for: error) ?? error
        }
    }

    func readMeasurements() async throws -> [HealthMeasurement] {
        guard let store else { throw HealthMeasurementReadFailure.unavailable }
        let query = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: Self.restingHeartRate)],
            anchor: nil
        )
        let result: HKAnchoredObjectQueryDescriptor<HKQuantitySample>.Result
        do {
            result = try await query.result(for: store)
        } catch {
            throw availabilityFailure(for: error) ?? error
        }

        let unit = HKUnit.count().unitDivided(by: .minute())
        return result.addedSamples.map { sample in
            let source = sample.sourceRevision.source
            return HealthMeasurement(
                id: sample.uuid,
                metric: .restingHeartRate,
                value: sample.quantity.doubleValue(for: unit),
                unit: .beatsPerMinute,
                startDate: sample.startDate,
                endDate: sample.endDate,
                source: .init(name: source.name, bundleIdentifier: source.bundleIdentifier)
            )
        }
    }

    private func availabilityFailure(for error: any Error) -> HealthMeasurementReadFailure? {
        switch (error as? HKError)?.code {
        case .errorDatabaseInaccessible: .protectedData
        case .errorHealthDataUnavailable, .errorHealthDataRestricted: .unavailable
        default: nil
        }
    }
}
