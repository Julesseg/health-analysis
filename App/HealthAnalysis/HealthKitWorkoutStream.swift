import Foundation
import HealthAnalysisCore
import HealthKit

enum HealthKitWorkoutStream {
    private static let workoutType = HKObjectType.workoutType()
    private static let runningDistance = HKQuantityType(.distanceWalkingRunning)
    static let query = HealthKitMeasurementQuery(
        type: workoutType,
        predicate: .workout(),
        additionalReadTypes: [runningDistance]
    ) { queryID, anchor, samples, deleted in
        HealthMeasurementChanges(
            queryID: queryID, anchor: anchor, added: [], deleted: deleted, workouts: samples.map(workout)
        )
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
