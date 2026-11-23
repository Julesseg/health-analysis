import Foundation

public enum ActivityTrackingVariable: String, CaseIterable, Codable, Identifiable, Sendable {
    case workoutDuration
    case runningDuration
    case runningDistance

    public enum Unit: Sendable {
        case seconds
        case meters
    }

    public var id: Self { self }

    public var unit: Unit {
        self == .runningDistance ? .meters : .seconds
    }

    var analysisName: String {
        switch self {
        case .workoutDuration: "Workout duration"
        case .runningDuration: "Running duration"
        case .runningDistance: "Running distance"
        }
    }

    func includes(_ workout: HealthWorkout) -> Bool {
        self == .workoutDuration || workout.activity == .running
    }

    fileprivate func value(of workout: HealthWorkout) -> Double? {
        let value = switch self {
        case .workoutDuration, .runningDuration: Optional(workout.activeDurationSeconds)
        case .runningDistance: workout.runningDistanceMeters
        }
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

public struct DailyActivityHistory: Sendable {
    public struct Day: Identifiable, Sendable {
        public enum Value: Equatable, Sendable {
            case observed(Double)
            case missingValue
            case overlappingWorkouts
        }

        public var id: Date { date }
        public let date: Date
        public let value: Value
        public let workouts: [HealthWorkout]
    }

    public struct Coverage: Sendable {
        public let firstRecordedDay: Date
        public let latestRecordedDay: Date
        public let recordedDays: Int
        public let daysWithValues: Int
        public let daysWithoutWorkouts: Int
    }

    public let days: [Day]
    public let coverage: Coverage?

    init(workouts: [HealthWorkout], variable: ActivityTrackingVariable, calendar: Calendar) {
        var signatures = Set<WorkoutSignature>()
        let distinct = workouts.filter { signatures.insert(WorkoutSignature($0)).inserted }
        let overlapping = overlappingWorkoutIDs(in: distinct)
        let byDay = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.endDate) }
        let distinctByDay = Dictionary(grouping: distinct) { calendar.startOfDay(for: $0.endDate) }
        days = byDay.keys.sorted(by: >).map { date in
            let records = distinctByDay[date, default: []]
            let value: Day.Value
            if records.contains(where: { overlapping.contains($0.id) }) {
                value = .overlappingWorkouts
            } else {
                let values = records.compactMap(variable.value(of:))
                let total = values.reduce(0, +)
                value = values.count == records.count && total.isFinite ? .observed(total) : .missingValue
            }
            return Day(date: date, value: value, workouts: byDay[date, default: []])
        }
        guard let first = days.last?.date, let latest = days.first?.date else {
            coverage = nil
            return
        }
        let span = (calendar.dateComponents([.day], from: first, to: latest).day ?? 0) + 1
        let observedDays = days.count { if case .observed = $0.value { true } else { false } }
        coverage = Coverage(firstRecordedDay: first, latestRecordedDay: latest, recordedDays: days.count,
                            daysWithValues: observedDays, daysWithoutWorkouts: max(0, span - days.count))
    }
}

private struct WorkoutSignature: Hashable {
    let activity: HealthWorkout.Activity
    let start: Date
    let end: Date
    let activeSeconds: Double
    let runningMeters: Double?

    init(_ workout: HealthWorkout) {
        activity = workout.activity
        start = workout.startDate
        end = workout.endDate
        activeSeconds = workout.activeDurationSeconds
        runningMeters = workout.runningDistanceMeters
    }
}

private func overlappingWorkoutIDs(in workouts: [HealthWorkout]) -> Set<UUID> {
    var furthestEnding: HealthWorkout?
    var overlapping = Set<UUID>()
    for workout in workouts.sorted(by: { $0.startDate < $1.startDate }) where workout.startDate < workout.endDate {
        if let previous = furthestEnding, workout.startDate < previous.endDate {
            overlapping.insert(previous.id)
            overlapping.insert(workout.id)
        }
        if furthestEnding.map({ $0.endDate < workout.endDate }) ?? true {
            furthestEnding = workout
        }
    }
    return overlapping
}

extension HealthMeasurementHistory {
    public func preferredWorkoutSource(for variable: ActivityTrackingVariable) -> HealthMeasurement.Source? {
        preferredSource(for: variable.preferenceKey)
    }

    public func workoutSources(for variable: ActivityTrackingVariable) -> [HealthMeasurement.Source] {
        let records = workouts.reversed().filter(variable.includes).map(\.source)
        return availableSources(records, preferred: preferredWorkoutSource(for: variable))
    }

    public func setPreferredWorkoutSource(
        _ bundleIdentifier: String?, for variable: ActivityTrackingVariable
    ) throws(PreferenceFailure) {
        try setPreferredSource(bundleIdentifier, for: variable.preferenceKey, among: workoutSources(for: variable))
    }

    public func activityHistory(
        for variable: ActivityTrackingVariable, calendar: Calendar = .current
    ) -> DailyActivityHistory {
        let preferredID = preferredWorkoutSource(for: variable)?.bundleIdentifier
        let eligible = workouts.filter {
            variable.includes($0) && (preferredID == nil || $0.source.bundleIdentifier == preferredID)
        }
        return DailyActivityHistory(workouts: eligible, variable: variable, calendar: calendar)
    }
}

extension ActivityTrackingVariable {
    var preferenceKey: HealthMeasurement.Metric {
        HealthMeasurement.Metric(rawValue: "workout.\(rawValue)")
    }
}
