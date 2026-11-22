import HealthAnalysisCore
import HealthKit
import SwiftUI

struct ActivitySection: View {
    let history: HealthMeasurementHistory

    var body: some View {
        Section("Activity") {
            ForEach(ActivityTrackingVariable.allCases) { variable in
                NavigationLink(variable.title) {
                    ActivityHistoryView(history: history, variable: variable)
                }
            }
        }
    }
}

private struct ActivityHistoryView: View {
    let history: HealthMeasurementHistory
    let variable: ActivityTrackingVariable

    @Environment(\.calendar) private var calendar
    @State private var preferenceSaveFailed = false

    private var selectedSource: Binding<String?> {
        Binding {
            history.preferredWorkoutSource(for: variable)?.bundleIdentifier
        } set: { identifier in
            do {
                try history.setPreferredWorkoutSource(identifier, for: variable)
                preferenceSaveFailed = false
            } catch {
                preferenceSaveFailed = true
            }
        }
    }

    var body: some View {
        let daily = history.activityHistory(for: variable, calendar: calendar)
        let sources = history.workoutSources(for: variable)
        List {
            Section {
                HealthReadStatus(history: history, showsInitialState: false)
                if let lastChecked = history.lastSuccessfulReadAt {
                    LabeledContent("Last successful check") {
                        Text(lastChecked, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                    }
                }
                Button("Refresh Health measurements") {
                    Task { await history.refresh() }
                }
                .disabled(history.readState == .loading)
                NavigationLink("Health access and sources") {
                    HealthAccessAndSourcesView(history: history)
                }
            }
            if !sources.isEmpty {
                Section {
                    Picker("Preferred source", selection: selectedSource) {
                        Text("All imported sources").tag(nil as String?)
                        ForEach(sources, id: \.bundleIdentifier) { source in
                            Text("\(source.name) (\(source.bundleIdentifier))")
                                .tag(Optional(source.bundleIdentifier))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("activity.preferredSource")
                    if preferenceSaveFailed {
                        Text("Couldn’t save the preferred source. Try again.")
                    }
                }
            }
            if let coverage = daily.coverage {
                ActivityCoverageSection(coverage: coverage)
                Section {
                    ForEach(daily.days) { day in
                        NavigationLink {
                            ActivityDayView(day: day, variable: variable)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.date, format: .dateTime.year().month(.abbreviated).day())
                                ActivityDailyValue(value: day.value, unit: variable.unit)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("activity.day")
                    }
                } header: {
                    Text("Daily history")
                } footer: {
                    Text("Workouts count on the date they end. Days without workout records have no total.")
                }
            } else {
                Section("Daily history") {
                    if history.preferredWorkoutSource(for: variable) != nil {
                        Text("No imported workouts for this source.")
                    } else {
                        Text("No readable workouts for this variable")
                    }
                }
            }
        }
        .navigationTitle(variable.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ActivityCoverageSection: View {
    let coverage: DailyActivityHistory.Coverage

    var body: some View {
        Section("Coverage") {
            LabeledContent("First recorded day") {
                Text(coverage.firstRecordedDay, format: .dateTime.year().month(.abbreviated).day())
            }
            LabeledContent("Latest recorded day") {
                Text(coverage.latestRecordedDay, format: .dateTime.year().month(.abbreviated).day())
            }
            LabeledContent("Days with a total") {
                Text(coverage.daysWithValues, format: .number)
            }
            LabeledContent("Days with workout records") {
                Text(coverage.recordedDays, format: .number)
            }
            LabeledContent("Days without workout records in this range") {
                Text(coverage.daysWithoutWorkouts, format: .number)
            }
            .accessibilityIdentifier("activity.coverage.gaps")
        }
    }
}

private struct ActivityDayView: View {
    let day: DailyActivityHistory.Day
    let variable: ActivityTrackingVariable

    var body: some View {
        List {
            Section("Daily total") {
                ActivityDailyValue(value: day.value, unit: variable.unit)
                    .accessibilityIdentifier("activity.dailyTotal")
            }
            Section {
                ForEach(day.workouts) { workout in
                    WorkoutRecordView(workout: workout)
                }
            } header: {
                Text("Imported workouts")
            } footer: {
                Text("Matching copies are counted once. Overlapping workouts with different details make the total unavailable.")
            }
        }
        .navigationTitle(day.date.formatted(.dateTime.year().month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ActivityDailyValue: View {
    let value: DailyActivityHistory.Day.Value
    let unit: ActivityTrackingVariable.Unit

    var body: some View {
        switch value {
        case .observed(let amount):
            ActivityAmount(value: amount, unit: unit)
        case .missingValue:
            Text("Total unavailable because workout values are missing")
        case .overlappingWorkouts:
            Text("Total unavailable because workouts overlap")
        }
    }
}

private struct WorkoutRecordView: View {
    let workout: HealthWorkout

    var body: some View {
        let timestamp = Date.FormatStyle.dateTime.year().month(.abbreviated).day().hour().minute()
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.activity.title)
                .font(.headline)
            Text("\(workout.startDate, format: timestamp) – \(workout.endDate, format: timestamp)")
            LabeledContent("Active duration") {
                ActivityAmount(value: workout.activeDurationSeconds, unit: .seconds)
            }
            if workout.activity == .running {
                LabeledContent("Distance") {
                    if let distance = workout.runningDistanceMeters {
                        ActivityAmount(value: distance, unit: .meters)
                    } else {
                        Text("Unavailable")
                    }
                }
            }
            LabeledContent("Source", value: workout.source.name)
            Text(workout.source.bundleIdentifier)
                .foregroundStyle(.secondary)
            if let version = workout.sourceVersion {
                LabeledContent("Source version", value: version)
            }
            if let product = workout.sourceProductType {
                LabeledContent("Source product", value: product)
            }
            if let timeZone = workout.timeZoneIdentifier {
                LabeledContent("Workout time zone", value: timeZone)
            }
        }
    }
}

private struct ActivityAmount: View {
    let value: Double
    let unit: ActivityTrackingVariable.Unit

    var body: some View {
        switch unit {
        case .seconds:
            Text(Duration.seconds(value), format: .units(allowed: [.hours, .minutes, .seconds], width: .wide))
        case .meters:
            Text(
                Measurement(value: value / 1_000, unit: UnitLength.kilometers),
                format: .measurement(width: .wide, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...3)))
            )
        }
    }
}

extension ActivityTrackingVariable {
    var title: LocalizedStringKey {
        switch self {
        case .workoutDuration: "Workout duration"
        case .runningDuration: "Running duration"
        case .runningDistance: "Running distance"
        }
    }
}

private extension HealthWorkout.Activity {
    var title: LocalizedStringKey {
        switch self {
        case .running:
            "Running"
        case .other(let rawValue):
            switch HKWorkoutActivityType(rawValue: rawValue) {
            case .cycling: "Cycling"
            case .hiking: "Hiking"
            case .swimming: "Swimming"
            case .walking: "Walking"
            default: "Workout (type \(rawValue))"
            }
        }
    }
}
