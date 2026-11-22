import Foundation
import HealthAnalysisCore
import HealthKit

struct HealthKitMeasurementQuery: Sendable {
    let readTypes: Set<HKObjectType>
    private let queryID: String
    private let read: @Sendable (HKHealthStore, String, HKQueryAnchor?, Bool) async throws -> HealthMeasurementChanges

    init<Sample: HKSample>(
        type: HKSampleType,
        predicate: HKSamplePredicate<Sample>,
        additionalReadTypes: Set<HKObjectType> = [],
        makeChanges: @escaping @Sendable (String, Data, [Sample], [UUID]) -> HealthMeasurementChanges
    ) {
        queryID = "\(type.identifier).all.v1"
        readTypes = additionalReadTypes.union([type])
        read = { store, queryID, previousAnchor, includingPreviouslySaved in
            // Access changes can expose older records. The saved anchor still supplies deletions.
            let fullRead = includingPreviouslySaved && previousAnchor != nil
                ? try await Self.query(predicate, after: nil, in: store)
                : nil
            let delta = try await Self.query(predicate, after: previousAnchor, in: store)
            let anchor = try NSKeyedArchiver.archivedData(withRootObject: delta.newAnchor, requiringSecureCoding: true)
            return makeChanges(
                queryID,
                anchor,
                (fullRead?.addedSamples ?? []) + delta.addedSamples,
                ((fullRead?.deletedObjects ?? []) + delta.deletedObjects).map(\.uuid)
            )
        }
    }

    init<Sample: HKSample>(
        type: HKSampleType,
        predicate: HKSamplePredicate<Sample>,
        measurement: @escaping @Sendable (Sample) -> HealthMeasurement?
    ) {
        self.init(type: type, predicate: predicate) { queryID, anchor, samples, deleted in
            HealthMeasurementChanges(
                queryID: queryID, anchor: anchor, added: samples.compactMap(measurement), deleted: deleted
            )
        }
    }

    func changes(
        in store: HKHealthStore, after anchors: [String: Data], includingPreviouslySaved: Bool
    ) async throws -> HealthMeasurementChanges {
        var previousAnchor: HKQueryAnchor?
        if let data = anchors[queryID] {
            guard let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) else {
                throw HealthMeasurementReadFailure.read
            }
            previousAnchor = decoded
        }

        return try await read(store, queryID, previousAnchor, includingPreviouslySaved)
    }

    private static func query<Sample: HKSample>(
        _ predicate: HKSamplePredicate<Sample>, after anchor: HKQueryAnchor?, in store: HKHealthStore
    ) async throws -> HKAnchoredObjectQueryDescriptor<Sample>.Result {
        try await HKAnchoredObjectQueryDescriptor(predicates: [predicate], anchor: anchor).result(for: store)
    }
}
