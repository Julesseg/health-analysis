import Foundation
import HealthAnalysisCore
import SwiftUI

struct HRVHistoryView: View {
    @Environment(\.calendar) private var calendar
    let history: HealthMeasurementHistory

    var body: some View {
        List {
            Section {
                HealthReadStatus(history: history, showsEmptyHistory: false)
                if let lastChecked = history.lastSuccessfulReadAt {
                    LabeledContent("Last successful check") {
                        Text(lastChecked, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                    }
                }
                Button("Refresh Health measurements") {
                    Task { await history.refresh() }
                }
                .disabled(history.readState == .loading)
            }
            ForEach(HRVSeries.StoredType.allCases, id: \.self) { type in
                Section(type.storageLabel) {
                    let series = history.hrvSeries(for: type, calendar: calendar)
                    ForEach(series, id: \.source.bundleIdentifier) { item in
                        NavigationLink {
                            HRVSeriesView(history: history, type: type, source: item.source)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: item.source.name)
                                Text(verbatim: item.source.bundleIdentifier)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("hrv.series.\(type.rawValue).\(item.source.bundleIdentifier)")
                    }
                    if series.isEmpty {
                        if type == .rmssd && !HealthKitHRVStream.supportsRMSSD {
                            Text("Reading RMSSD records requires iOS 27 or later.")
                        } else {
                            Text("No readable records for this HealthKit type.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Heart rate variability")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HRVSeriesView: View {
    @Environment(\.calendar) private var calendar
    let history: HealthMeasurementHistory
    let type: HRVSeries.StoredType
    let source: HealthMeasurement.Source

    var body: some View {
        let series = history.hrvSeries(for: type, calendar: calendar)
            .first { $0.source.bundleIdentifier == source.bundleIdentifier }
        List {
            Section("Measurement meaning") {
                Text(type.storageLabel)
                LabeledContent("Original HRV measure") { Text("Unverified") }
                LabeledContent("Original summary") { Text("Unverified") }
                if let series {
                    Text(series.analysisLimitation.message)
                } else {
                    Text("No readable records for this source.")
                }
            }
            if let series {
                let coverage = series.coverage
                Section("Coverage") {
                    LabeledContent("Imported records") {
                        Text(coverage.recordCount, format: .number)
                    }
                    LabeledContent("Days with sample starts") {
                        Text(coverage.measuredDays, format: .number)
                    }
                    LabeledContent("Days without measurements in this range") {
                        Text(coverage.daysWithoutMeasurements, format: .number)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Days without measurements in this range"))
                    .accessibilityValue(Text(coverage.daysWithoutMeasurements, format: .number))
                    .accessibilityIdentifier("hrv.coverage.daysWithoutMeasurements")
                    LabeledContent("First sample start") {
                        Text(coverage.firstMeasurement, format: .dateTime.year().month(.abbreviated).day())
                    }
                    LabeledContent("Latest sample start") {
                        Text(coverage.latestMeasurement, format: .dateTime.year().month(.abbreviated).day())
                    }
                }
                Section("History") {
                    ForEach(series.records) { record in
                        NavigationLink {
                            HRVRecordView(record: record, type: type)
                        } label: {
                            VStack(alignment: .leading) {
                                HealthMeasurementValue(measurement: record)
                                Text(record.startDate, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("hrv.record.\(record.id.uuidString)")
                    }
                }
            }
        }
        .navigationTitle(series?.source.name ?? source.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HRVRecordView: View {
    let record: HealthMeasurement
    let type: HRVSeries.StoredType

    var body: some View {
        let provenance = record.hrvProvenance
        List {
            Section {
                HealthMeasurementValue(measurement: record)
                Text(type.storageLabel)
                LabeledContent("Sample start") { Text(record.startDate, format: timestamp) }
                LabeledContent("Sample end") { Text(record.endDate, format: timestamp) }
                LabeledContent("Recorded time zone") { metadata(record.timeZoneIdentifier) }
                if let provenance {
                    LabeledContent("Values in HealthKit sample") {
                        Text(provenance.quantityCount, format: .number)
                    }
                }
            }
            Section("Saving source") {
                LabeledContent("Source") { Text(verbatim: record.source.name) }
                LabeledContent("Bundle identifier") { Text(verbatim: record.source.bundleIdentifier) }
                LabeledContent("Source version") { metadata(record.sourceRevision?.version) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Source version"))
                    .accessibilityValue(metadata(record.sourceRevision?.version))
                    .accessibilityIdentifier("hrv.record.sourceVersion")
                LabeledContent("Source product type") { metadata(record.sourceRevision?.productType) }
                LabeledContent("Source OS version") {
                    let version = record.sourceRevision?.operatingSystemVersion
                    metadata(version == "0.0.0" ? nil : version)
                }
                if let manufacturer = provenance?.deviceManufacturer {
                    LabeledContent("Sample device manufacturer") { Text(verbatim: manufacturer) }
                }
                if let model = provenance?.deviceModel {
                    LabeledContent("Sample device model") { Text(verbatim: model) }
                }
            }
            Section("Record identity") {
                LabeledContent("Sample UUID") { Text(verbatim: record.id.uuidString) }
                LabeledContent("Sync identifier") { metadata(provenance?.syncIdentifier) }
                LabeledContent("Sync version") {
                    if let version = provenance?.syncVersion {
                        Text(version, format: .number.grouping(.never))
                    } else {
                        Text("Not recorded")
                    }
                }
            }
        }
        .navigationTitle("HRV sample")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var timestamp: Date.FormatStyle {
        .dateTime.year().month(.abbreviated).day().hour().minute().second().timeZone(.iso8601(.long))
    }

    private func metadata(_ value: String?) -> Text {
        if let value { Text(verbatim: value) } else { Text("Not recorded") }
    }
}

extension HRVSeries.StoredType {
    var storageLabel: LocalizedStringKey {
        switch self {
        case .sdnn: "Stored in HealthKit as SDNN"
        case .rmssd: "Stored in HealthKit as RMSSD"
        }
    }
}

private extension HRVSeries.AnalysisLimitation {
    var message: LocalizedStringKey {
        switch self {
        case .unverifiedOriginalMeasureAndSummary:
            "Analysis unavailable until the original HRV measure and how it was summarized are verified."
        }
    }
}
