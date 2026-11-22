import Foundation
import HealthAnalysisCore
import HealthKit

enum HealthKitWorkoutStream {
    private static let workoutType = HKObjectType.workoutType()
    private static let runningDistance = HKQuantityType(.distanceWalkingRunning)
    private static let queryID = "\(workoutType.identifier).all.v1"

    static var readTypes: Set<HKObjectType> { [workoutType, runningDistance] }

    static func readChanges(
        after anchors: [String: Data], includingPreviouslySaved: Bool, in store: HKHealthStore
    ) async throws -> HealthMeasurementChanges {
        var previousAnchor: HKQueryAnchor?
        if let data = anchors[queryID] {
            guard let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) else {
                throw HealthMeasurementReadFailure.read
            }
            previousAnchor = decoded
        }

        let fullRead = includingPreviouslySaved && previousAnchor != nil
            ? try await query(after: nil, in: store)
            : nil
        let changes = try await query(after: previousAnchor, in: store)
        let anchor = try NSKeyedArchiver.archivedData(withRootObject: changes.newAnchor, requiringSecureCoding: true)
        let added = (fullRead?.addedSamples ?? []) + changes.addedSamples
        let deleted = (fullRead?.deletedObjects ?? []) + changes.deletedObjects
        return HealthMeasurementChanges(
            queryID: queryID, anchor: anchor, added: [], deleted: deleted.map(\.uuid), workouts: added.map(workout)
        )
    }

    private static func query(
        after anchor: HKQueryAnchor?, in store: HKHealthStore
    ) async throws -> HKAnchoredObjectQueryDescriptor<HKWorkout>.Result {
        try await HKAnchoredObjectQueryDescriptor(predicates: [.workout()], anchor: anchor).result(for: store)
    }

    private static func workout(from sample: HKWorkout) -> HealthWorkout {
        let revision = sample.sourceRevision
        let isRun = sample.workoutActivityType == .running
        let distance = isRun ? (sample.statistics(for: runningDistance)?.sumQuantity() ?? sample.totalDistance) : nil
        let distanceMeters = distance?.doubleValue(for: .meter())
        return HealthWorkout(
            id: sample.uuid,
            activity: isRun ? .running : .other(healthKitType: sample.workoutActivityType.rawValue),
            startDate: sample.startDate,
            endDate: sample.endDate,
            activeDurationSeconds: sample.duration,
            runningDistanceMeters: distanceMeters.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
            source: .init(name: revision.source.name, bundleIdentifier: revision.source.bundleIdentifier),
            sourceVersion: revision.version,
            sourceProductType: revision.productType,
            timeZoneIdentifier: sample.metadata?[HKMetadataKeyTimeZone] as? String
        )
    }
}
