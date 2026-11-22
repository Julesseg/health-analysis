import HealthAnalysisCore
import SwiftUI

struct HealthMeasurementHistoryView: View {
    let history: HealthMeasurementHistory

    var body: some View {
        List {
            Section {
                HealthReadStatus(history: history)
                if let lastChecked = history.lastSuccessfulReadAt {
                    LabeledContent("Last successful check") {
                        Text(lastChecked, format: .dateTime.month(.abbreviated).day().hour().minute())
                    }
                }
                Button("Refresh Health measurements") {
                    Task { await history.refresh() }
                }
                .disabled(history.readState == .loading)
            }
            if let first = history.history.last, let latest = history.latest {
                Section("Coverage") {
                    LabeledContent("Imported records") {
                        Text(history.history.count, format: .number)
                    }
                    LabeledContent("First measurement") {
                        Text(first.startDate, format: .dateTime.year().month(.abbreviated).day())
                    }
                    LabeledContent("Latest measurement") {
                        Text(latest.startDate, format: .dateTime.year().month(.abbreviated).day())
                    }
                }
                Section("History") {
                    ForEach(history.history) { measurement in
                        HealthMeasurementRow(measurement: measurement)
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
        var seen: Set<String> = []
        return history.history.compactMap { measurement in
            let source = measurement.source
            return seen.insert(source.bundleIdentifier).inserted ? source : nil
        }
    }

    var body: some View {
        List {
            Section {
                Text("Health Analysis reads resting heart rate to show your measurements over time.")
                Button("Request read access") {
                    Task { await history.requestAccessAndRefresh() }
                }
                .disabled(history.readState == .loading)
                HealthReadStatus(history: history, showsInitialState: false)
            }
            Section("Imported sources") {
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
