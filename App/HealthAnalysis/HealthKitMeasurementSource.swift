import Foundation
import HealthAnalysisCore
import HealthKit

struct HealthKitMeasurementSource: HealthMeasurementSource {
    private let store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil

    private static let queries: [HealthKitMeasurementQuery] = [
        restingHeartRate,
        .sleep,
    ]

    private static let restingHeartRate: HealthKitMeasurementQuery = {
        let type = HKQuantityType(.restingHeartRate)
        return HealthKitMeasurementQuery(type: type, predicate: .quantitySample(type: type)) { sample in
            let unit = HKUnit.count().unitDivided(by: .minute())
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
    }()

    func requestReadAccess() async throws {
        guard let store else { throw HealthMeasurementReadFailure.unavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: Set(Self.queries.flatMap(\.readTypes)))
        } catch {
            throw availabilityFailure(for: error) ?? error
        }
    }

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        guard let store else { throw HealthMeasurementReadFailure.unavailable }
        do {
            var changes: [HealthMeasurementChanges] = []
            for query in Self.queries {
                changes.append(try await query.changes(
                    in: store, after: anchors, includingPreviouslySaved: includingPreviouslySaved
                ))
            }
            return changes
        } catch {
            throw availabilityFailure(for: error) ?? error
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
