import Foundation
import HealthAnalysisCore
import HealthKit

struct HealthKitMeasurementSource: HealthMeasurementSource {
    private let store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    private static let restingHeartRate = HKQuantityType(.restingHeartRate)
    private static let queryID = "\(restingHeartRate.identifier).all.v1"

    func requestReadAccess() async throws {
        guard let store else { throw HealthMeasurementReadFailure.unavailable }
        do {
            let readTypes = HealthKitWorkoutStream.readTypes.union([Self.restingHeartRate])
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            throw availabilityFailure(for: error) ?? error
        }
    }

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        guard let store else { throw HealthMeasurementReadFailure.unavailable }
        var previousAnchor: HKQueryAnchor?
        if let data = anchors[Self.queryID] {
            guard let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) else {
                throw HealthMeasurementReadFailure.read
            }
            previousAnchor = decoded
        }

        do {
            // Access changes may expose older samples. Still read from the saved anchor for deletions.
            let fullRead = includingPreviouslySaved && previousAnchor != nil
                ? try await query(after: nil, in: store)
                : nil
            let changes = try await query(after: previousAnchor, in: store)
            let anchor = try NSKeyedArchiver.archivedData(withRootObject: changes.newAnchor, requiringSecureCoding: true)
            let added = (fullRead?.addedSamples ?? []) + changes.addedSamples
            let deleted = (fullRead?.deletedObjects ?? []) + changes.deletedObjects
            let workouts = try await HealthKitWorkoutStream.readChanges(
                after: anchors, includingPreviouslySaved: includingPreviouslySaved, in: store
            )
            return [
                .init(queryID: Self.queryID, anchor: anchor, added: added.map(measurement), deleted: deleted.map(\.uuid)),
                workouts,
            ]
        } catch {
            throw availabilityFailure(for: error) ?? error
        }
    }

    private func query(
        after anchor: HKQueryAnchor?, in store: HKHealthStore
    ) async throws -> HKAnchoredObjectQueryDescriptor<HKQuantitySample>.Result {
        try await HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: Self.restingHeartRate)],
            anchor: anchor
        ).result(for: store)
    }

    private func measurement(from sample: HKQuantitySample) -> HealthMeasurement {
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

    private func availabilityFailure(for error: any Error) -> HealthMeasurementReadFailure? {
        switch (error as? HKError)?.code {
        case .errorDatabaseInaccessible: .protectedData
        case .errorHealthDataUnavailable, .errorHealthDataRestricted: .unavailable
        default: nil
        }
    }
}
