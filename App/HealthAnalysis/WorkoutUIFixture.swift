#if DEBUG
import Foundation
import HealthAnalysisCore

struct WorkoutUIFixture: HealthMeasurementSource {
    private let queryID = "workouts"
    private let date = Date(timeIntervalSince1970: 1_763_380_800)
    private let watch = HealthMeasurement.Source(name: "Watch", bundleIdentifier: "fixture.watch")
    private let bridge = HealthMeasurement.Source(name: "Bridge", bundleIdentifier: "fixture.bridge")

    func requestReadAccess() async throws {}

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        let run = workout(id: "80000000-0000-0000-0000-000000000001", date: date, meters: 5_000, source: watch)
        let copy = workout(id: "80000000-0000-0000-0000-000000000002", date: date, meters: 5_000, source: bridge)
        var records = [run, copy]
        let isReplay = anchors[queryID] != nil
        if isReplay {
            records.append(workout(id: "80000000-0000-0000-0000-000000000003",
                                   date: date.addingTimeInterval(-172_800), meters: 0, source: watch))
        }
        return [.init(queryID: queryID, anchor: Data([isReplay ? 2 : 1]), added: [], workouts: records)]
    }

    private func workout(id: String, date: Date, meters: Double, source: HealthMeasurement.Source) -> HealthWorkout {
        HealthWorkout(
            id: UUID(uuidString: id)!, activity: .running, startDate: date,
            endDate: date.addingTimeInterval(1_800), activeDurationSeconds: 1_600,
            runningDistanceMeters: meters, source: source
        )
    }
}
#endif
