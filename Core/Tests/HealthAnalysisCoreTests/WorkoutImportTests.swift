import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct WorkoutImportTests {
    @Test func importedWorkoutsExposeTimedDailyValuesAndMissingCoverage() async throws {
        let run = workout(on: 1, activeSeconds: 1_500, distanceMeters: 5_000)
        let ride = workout(on: 1, minute: 600, activity: .other(healthKitType: 13), activeSeconds: 1_200)
        let zeroDistance = workout(on: 3, distanceMeters: 0)
        let unknownDistance = workout(on: 4)
        let anotherRun = workout(on: 4, minute: 600, distanceMeters: 2_000)
        let source = WorkoutFixtureSource { _ in
            [.init(queryID: "workouts", anchor: Data([1]), added: [],
                   workouts: [ride, run, zeroDistance, unknownDistance, anotherRun])]
        }
        let app = HealthAnalysisApplication(healthSource: source)
        await app.healthMeasurements.refresh()

        let activities = app.healthMeasurements.activityHistory(for: .workoutDuration, calendar: calendar)
        let running = app.healthMeasurements.activityHistory(for: .runningDuration, calendar: calendar)
        let distance = app.healthMeasurements.activityHistory(for: .runningDistance, calendar: calendar)
        #expect(activities.days.map(\.value) == [.observed(3_600), .observed(1_800), .observed(2_700)])
        #expect(running.days.map(\.value) == [.observed(3_600), .observed(1_800), .observed(1_500)])
        #expect(distance.days.map(\.value) == [.missingValue, .observed(0), .observed(5_000)])
        #expect(distance.coverage?.recordedDays == 3)
        #expect(distance.coverage?.daysWithoutWorkouts == 1)
        #expect(distance.coverage?.daysWithValues == 2)
        #expect(distance.days.last?.workouts == [run])
        #expect(distance.days.last?.workouts.first?.endDate == run.startDate.addingTimeInterval(1_800))
        #expect(app.overview.hasReadableMeasurements)
    }

    @Test func repeatedImportsCollapseMatchingCopiesAndWithholdAmbiguousOverlaps() async {
        let run = workout(on: 1, distanceMeters: 5_000)
        let copy = workout(on: 1, distanceMeters: 5_000, source: .init(name: "Bridge", bundleIdentifier: "fixture.bridge"))
        let adjacent = workout(on: 1, minute: 510, distanceMeters: 1_000)
        let beforeMidnight = workout(on: 2, minute: 1_400, distanceMeters: 3_000)
        let afterMidnight = workout(on: 2, minute: 1_425, distanceMeters: 4_000)
        let source = WorkoutFixtureSource { _ in
            [.init(queryID: "workouts", anchor: Data([1]), added: [],
                   workouts: [run, copy, adjacent, beforeMidnight, afterMidnight])]
        }
        let app = HealthAnalysisApplication(healthSource: source)
        await app.healthMeasurements.refresh()
        await app.healthMeasurements.refresh()

        let distance = app.healthMeasurements.activityHistory(for: .runningDistance, calendar: calendar)
        #expect(distance.days.map(\.value) == [.overlappingWorkouts, .overlappingWorkouts, .observed(6_000)])
        #expect(distance.days.last?.workouts.count == 3)
        #expect(Set(app.healthMeasurements.workouts.map(\.id)) == [run.id, copy.id, adjacent.id, beforeMidnight.id, afterMidnight.id])
        #expect(distance.coverage?.daysWithValues == 1)
    }

    @Test func sourcePreferencesAndWorkoutCorrectionsSurviveReopeningTheStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.json")
        let watch = workout(on: 1, distanceMeters: 5_000)
        let bridge = HealthMeasurement.Source(name: "Bridge", bundleIdentifier: "fixture.bridge")
        let old = workout(on: 1, distanceMeters: 5_400, source: bridge)
        let corrected = workout(on: 1, distanceMeters: 5_200, source: bridge)
        let initial = HealthAnalysisApplication(
            healthSource: WorkoutFixtureSource { _ in
                [.init(queryID: "workouts", anchor: Data([1]), added: [], workouts: [watch, old])]
            },
            healthHistoryStoreURL: url
        )
        await initial.healthMeasurements.refresh()

        #expect(initial.healthMeasurements.workoutSources(for: .runningDistance) == [bridge, watch.source])
        try initial.healthMeasurements.setPreferredWorkoutSource(bridge.bundleIdentifier, for: .runningDistance)
        #expect(initial.healthMeasurements.activityHistory(for: .runningDistance, calendar: calendar).days.first?.value == .observed(5_400))
        #expect(initial.healthMeasurements.activityHistory(for: .runningDuration, calendar: calendar).days.first?.value == .overlappingWorkouts)

        let updated = HealthAnalysisApplication(
            healthSource: WorkoutFixtureSource { anchors in
                guard anchors["workouts"] == Data([1]) else { throw HealthMeasurementReadFailure.read }
                return [.init(queryID: "workouts", anchor: Data([2]), added: [], deleted: [old.id], workouts: [corrected, old])]
            },
            healthHistoryStoreURL: url
        )
        await updated.healthMeasurements.refresh()
        #expect(updated.healthMeasurements.readState == .loaded)
        #expect(updated.healthMeasurements.preferredWorkoutSource(for: .runningDistance) == bridge)
        #expect(updated.healthMeasurements.activityHistory(for: .runningDistance, calendar: calendar).days.first?.workouts == [corrected])

        let replay = HealthAnalysisApplication(
            healthSource: WorkoutFixtureSource { anchors in
                guard anchors["workouts"] == Data([2]) else { throw HealthMeasurementReadFailure.read }
                return [.init(queryID: "workouts", anchor: Data([3]), added: [], workouts: [old, corrected])]
            },
            healthHistoryStoreURL: url
        )
        await replay.healthMeasurements.refresh()
        #expect(replay.healthMeasurements.readState == .loaded)
        #expect(replay.healthMeasurements.activityHistory(for: .runningDistance, calendar: calendar).days.first?.value == .observed(5_200))
        #expect(Set(replay.healthMeasurements.workouts.map(\.id)) == [watch.id, corrected.id])
    }

    @Test func runningHistoryIsEditableInPresetsAndKeepsSourcesAndWorkoutTimingWhenPaired() async throws {
        let bridge = HealthMeasurement.Source(name: "Bridge", bundleIdentifier: "fixture.bridge")
        let run = workout(on: 2, minute: 1_425, activeSeconds: 1_600, distanceMeters: 5_000)
        let alternate = workout(on: 2, minute: 1_425, distanceMeters: 9_000, source: bridge)
        let missingDistance = workout(on: 4)
        let records = (3...5).map { day in
            let date = Date(timeIntervalSince1970: Double(day * 86_400 + 10_800))
            return HealthMeasurement(
                id: UUID(), metric: .restingHeartRate, value: 60, unit: .beatsPerMinute,
                startDate: date, endDate: date, source: bridge
            )
        }
        let source = WorkoutFixtureSource { anchors in
            switch anchors["activity"] {
            case nil:
                [.init(queryID: "activity", anchor: Data([1]), added: records, workouts: [run, alternate, missingDistance])]
            case Data([1]):
                [.init(queryID: "activity", anchor: Data([2]), added: [], deleted: [run.id])]
            default:
                throw HealthMeasurementReadFailure.protectedData
            }
        }
        let app = HealthAnalysisApplication(healthSource: source)
        await app.healthMeasurements.refresh()
        let zone = calendar.timeZone
        let cutoff = Date(timeIntervalSince1970: 6 * 86_400)
        let distance = AnalysisSeriesID.activity(.runningDistance)
        let resting = AnalysisSeriesID.health(metric: .restingHeartRate)
        #expect(throws: AnalysisRunFailure.chooseInputSource(distance)) {
            try app.analyze(.init(output: resting, inputs: [distance], timeZone: zone), asOf: cutoff)
        }
        try app.healthMeasurements.setPreferredWorkoutSource(run.source.bundleIdentifier, for: .runningDistance)
        let presets = app.analysisPresets(timeZone: zone, asOf: cutoff)
        let preset = try #require(presets.first { $0.output == resting && $0.inputs == [distance] })
        var edited = preset
        edited.history = .last90Days
        let forward = try app.analyze(edited, asOf: cutoff)
        let value = try #require(forward.observations.first?.inputs.first?.days.first)
        #expect(forward.observations.count == 1)
        #expect(value.value == 5)
        #expect(value.importedRecord?.source == run.source)
        #expect(value.importedRecord?.start == run.startDate)
        #expect(value.importedRecord?.end == run.endDate)
        #expect(forward.coverage.outputDaysWithoutCompleteInput == 2)

        let quantity = try app.manualLog.createQuantity(
            name: "Stress score", unit: "units", defaultValue: 10, startsOn: ManualLogDay(Date(timeIntervalSince1970: 0), timeZone: zone)
        )
        let manual = AnalysisSeriesID.manualQuantity(quantity.id)
        let reverse = try app.analyze(.init(output: distance, inputs: [manual], timeZone: zone), asOf: cutoff)
        #expect(reverse.observations.first?.outputAnchor == run.endDate)
        #expect(reverse.observations.first?.inputs.first?.date == Date(timeIntervalSince1970: 86_400))
        #expect(reverse.outputEvidence.first?.importedRecord?.start == run.startDate)

        let trackedOutput = AnalysisConfiguration(output: manual, inputs: [distance], timeZone: zone)
        let question = try app.savedAnalyses.save(trackedOutput)
        try app.savedAnalyses.setPinned(true, for: question.id)
        await app.refreshReconciledHealthInsights(asOf: cutoff, timeZone: zone)
        #expect(app.savedAnalyses.state(for: question.id).completed?.result.observations.count == 1)
        await app.healthMeasurements.refresh()
        await app.refreshReconciledHealthInsights(asOf: cutoff, timeZone: zone)
        let corrected = try #require(app.savedAnalyses.state(for: question.id).completed)
        #expect(corrected.result.observations.isEmpty)

        await app.healthMeasurements.refresh()
        await app.refreshReconciledHealthInsights(asOf: cutoff, timeZone: zone)
        #expect(app.savedAnalyses.state(for: question.id).completed?.updatedAt == corrected.updatedAt)
        #expect(app.savedAnalyses.state(for: question.id).failure == .analysis(.healthHistoryUnavailable(.protectedData)))
    }

    private let calendar = Calendar(identifier: .gregorian).settingUTC

    private func workout(
        on day: Int,
        minute: Int = 480,
        activity: HealthWorkout.Activity = .running,
        activeSeconds: Double = 1_800,
        distanceMeters: Double? = nil,
        id: UUID = UUID(),
        source: HealthMeasurement.Source = .init(name: "Watch", bundleIdentifier: "fixture.watch")
    ) -> HealthWorkout {
        let start = Date(timeIntervalSince1970: Double(day * 86_400 + minute * 60))
        return HealthWorkout(
            id: id, activity: activity, startDate: start, endDate: start.addingTimeInterval(1_800),
            activeDurationSeconds: activeSeconds, runningDistanceMeters: distanceMeters, source: source,
            sourceVersion: "5.2.0", timeZoneIdentifier: "Europe/Paris"
        )
    }
}

private struct WorkoutFixtureSource: HealthMeasurementSource {
    let changes: @Sendable ([String: Data]) throws -> [HealthMeasurementChanges]

    func requestReadAccess() async throws {}

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        try changes(anchors)
    }
}

private extension Calendar {
    var settingUTC: Self {
        var calendar = self
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
