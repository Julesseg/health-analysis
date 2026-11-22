import HealthAnalysisCore
import SwiftUI

struct HealthMeasurementHistoryView: View {
    let history: HealthMeasurementHistory
    let presentation: HealthMetricPresentation
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var preferenceSaveFailed = false
    private var metric: HealthMeasurement.Metric { presentation.metric }

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
                HealthReadStatus(history: history, showsEmptyHistory: false)
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
                    LabeledContent(presentation.recordCountTitle) {
                        Text(coverage.recordCount, format: .number)
                    }
                    LabeledContent("Days with measurements") {
                        Text(coverage.measuredDays, format: .number)
                    }
                    LabeledContent("Days without measurements in this range") {
                        Text(coverage.daysWithoutMeasurements, format: .number)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Days without measurements in this range"))
                    .accessibilityValue(Text(coverage.daysWithoutMeasurements, format: .number))
                    .accessibilityIdentifier("health.coverage.daysWithoutMeasurements")
                    LabeledContent(presentation.firstDateTitle) {
                        Text(verbatim: coverage.firstMeasurement.formatted(dateFormat(in: coverage.firstMeasurementTimeZone)))
                    }
                    LabeledContent(presentation.latestDateTitle) {
                        Text(verbatim: coverage.latestMeasurement.formatted(dateFormat(in: coverage.latestMeasurementTimeZone)))
                    }
                }
                Section("History") {
                    if metric == .sleepAnalysis {
                        SleepHistoryRows(episodes: history.sleepEpisodes)
                    } else {
                        ForEach(history.measurements(for: metric)) { measurement in
                            HealthMeasurementRow(measurement: measurement)
                        }
                    }
                }
            } else {
                Section("History") {
                    if metric == .sleepAnalysis {
                        SleepHistoryUnavailable(
                            hasRecords: !history.measurements(for: metric).isEmpty,
                            hasSelectedSource: history.preferredSource(for: metric) != nil
                        )
                    } else if history.preferredSource(for: metric) != nil {
                        Text("No imported measurements for this source.")
                    } else {
                        Text(history.hasReadableRecords ? presentation.emptyHistoryTitle : "No readable measurements")
                    }
                }
            }
        }
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dateFormat(in timeZone: TimeZone?) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.year().month(.abbreviated).day().locale(locale)
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        if let timeZone { format.timeZone = timeZone }
        return format
    }
}

struct HealthAccessAndSourcesView: View {
    let history: HealthMeasurementHistory

    var body: some View {
        let hrvTypes = HRVSeries.StoredType.allCases.map {
            HealthMetricPresentation(metric: $0.metric, title: $0.storageLabel)
        }
        let metricsWithSources = (HealthMetricPresentation.supported + hrvTypes)
            .filter { !history.sources(for: $0.metric).isEmpty }
        List {
            Section {
                Text("Health Analysis reads your resting heart rate, heart rate variability, sleep, workouts, and workout distance to show your history over time.")
                Button("Request read access") {
                    Task { await history.requestAccessAndRefresh() }
                }
                .disabled(history.readState == .loading)
                HealthReadStatus(history: history, showsInitialState: false)
            }
            Section("Imported sources") {
                if metricsWithSources.isEmpty {
                    Text("No imported sources")
                }
                ForEach(metricsWithSources) { metric in
                    Text(metric.title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(history.sources(for: metric.metric), id: \.bundleIdentifier) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name)
                            Text(source.bundleIdentifier)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Review in Apple Health") {
                Text("To review access, tap your profile in Apple Health, then Apps under Privacy.")
                Text("To review contributing sources, open a measurement in Apple Health and tap Data Sources & Access.")
            }
        }
        .navigationTitle("Health access and sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
