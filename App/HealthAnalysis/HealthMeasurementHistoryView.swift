import HealthAnalysisCore
import SwiftUI

struct HealthMeasurementHistoryView: View {
    let history: HealthMeasurementHistory
    @Environment(\.calendar) private var calendar
    @State private var preferenceSaveFailed = false
    private let metric = HealthMeasurement.Metric.restingHeartRate

    private var selectedSource: Binding<String?> {
        Binding {
            history.preferredSource(for: metric)?.bundleIdentifier
        } set: { identifier in
            do {
                try history.setPreferredSource(identifier, for: metric)
                preferenceSaveFailed = false
            } catch {
                preferenceSaveFailed = true
            }
        }
    }

    var body: some View {
        let sources = history.sources(for: metric)
        List {
            Section {
                HealthReadStatus(history: history)
                if let lastChecked = history.lastSuccessfulReadAt {
                    LabeledContent("Last successful check") {
                        Text(lastChecked, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                    }
                    .accessibilityIdentifier("health.lastSuccessfulCheck")
                }
                Button("Refresh Health measurements") {
                    Task { await history.refresh() }
                }
                .disabled(history.readState == .loading)
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
                    .accessibilityIdentifier("health.preferredSource")
                    if preferenceSaveFailed {
                        Text("Couldn’t save the preferred source. Try again.")
                    }
                }
            }
            if let coverage = history.coverage(for: metric, calendar: calendar) {
                Section("Coverage") {
                    LabeledContent("Imported records") {
                        Text(coverage.recordCount, format: .number)
                    }
                    LabeledContent("Days with measurements") {
                        Text(coverage.measuredDays, format: .number)
                    }
                    LabeledContent("Days without measurements in this range") {
                        Text(coverage.daysWithoutMeasurements, format: .number)
                    }
                    LabeledContent("First measurement") {
                        Text(coverage.firstMeasurement, format: .dateTime.year().month(.abbreviated).day())
                    }
                    LabeledContent("Latest measurement") {
                        Text(coverage.latestMeasurement, format: .dateTime.year().month(.abbreviated).day())
                    }
                }
                Section("History") {
                    ForEach(history.measurements(for: metric)) { measurement in
                        HealthMeasurementRow(measurement: measurement)
                    }
                }
            } else if history.hasReadableRecords || history.preferredSource(for: metric) != nil {
                Section("History") {
                    if history.preferredSource(for: metric) == nil {
                        Text("No imported resting heart rate measurements")
                    } else {
                        Text("No imported measurements for this source.")
                    }
                }
            }
        }
        .navigationTitle("Resting heart rate")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HealthAccessAndSourcesView: View {
    let history: HealthMeasurementHistory

    private var sources: [HealthMeasurement.Source] {
        history.sources(for: .restingHeartRate)
    }

    var body: some View {
        List {
            Section {
                Text("Health Analysis reads your resting heart rate, workouts, and workout distance to show your history over time.")
                Button("Request read access") {
                    Task { await history.requestAccessAndRefresh() }
                }
                .disabled(history.readState == .loading)
                HealthReadStatus(history: history, showsInitialState: false)
            }
            Section("Resting heart rate sources") {
                if sources.isEmpty {
                    Text("No imported sources")
                }
                ForEach(sources, id: \.bundleIdentifier) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name)
                        Text(source.bundleIdentifier)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Review in Apple Health") {
                Text("To review access, tap your profile in Apple Health, then Apps under Privacy.")
                Text("To review contributing sources, open Resting Heart Rate in Apple Health and tap Data Sources & Access.")
            }
        }
        .navigationTitle("Health access and sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
