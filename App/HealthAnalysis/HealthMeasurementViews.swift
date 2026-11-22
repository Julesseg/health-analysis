import Foundation
import HealthAnalysisCore
import SwiftUI

struct HealthMetricPresentation: Identifiable {
    @MainActor
    static let restingHeartRate = Self(
        metric: .restingHeartRate,
        title: "Resting heart rate",
        emptyHistoryTitle: "No imported resting heart rate measurements"
    )
    @MainActor
    static let supported: [Self] = [
        restingHeartRate,
        .sleep,
    ]

    let metric: HealthMeasurement.Metric
    let title: LocalizedStringKey
    var emptyHistoryTitle: LocalizedStringKey = "No readable measurements"
    var recordCountTitle: LocalizedStringKey = "Imported records"
    var firstDateTitle: LocalizedStringKey = "First measurement"
    var latestDateTitle: LocalizedStringKey = "Latest measurement"
    var id: HealthMeasurement.Metric { metric }
}

struct HealthMeasurementsSection: View {
    let history: HealthMeasurementHistory

    var body: some View {
        Section("Health measurements") {
            HealthReadStatus(history: history)
            ForEach(HealthMetricPresentation.supported) { presentation in
                NavigationLink(presentation.title) {
                    HealthMeasurementHistoryView(history: history, presentation: presentation)
                }
            }
            NavigationLink("Heart rate variability") {
                HRVHistoryView(history: history)
            }
            NavigationLink("Health access and sources") {
                HealthAccessAndSourcesView(history: history)
            }
        }
    }
}

struct LatestHealthMeasurementsSection: View {
    let history: HealthMeasurementHistory

    var body: some View {
        Section("Latest measurements") {
            HealthReadStatus(history: history)
            if let measurement = history.latest {
                HealthMeasurementRow(measurement: measurement, metricTitle: HealthMetricPresentation.restingHeartRate.title)
            } else if history.preferredSource(for: .restingHeartRate) != nil {
                Text("No imported measurements for this source.")
            } else if history.hasReadableRecords {
                Text(HealthMetricPresentation.restingHeartRate.emptyHistoryTitle)
            }
        }
    }
}

struct HealthReadStatus: View {
    let history: HealthMeasurementHistory
    var showsInitialState = true
    var showsEmptyHistory = true

    var body: some View {
        switch history.readState {
        case .idle:
            if showsInitialState && showsEmptyHistory && !history.hasReadableRecords {
                Text("No readable measurements")
            }
        case .loading:
            ProgressView("Checking Health measurements…")
                .accessibilityIdentifier("health.readProgress")
        case .loaded:
            if showsEmptyHistory && !history.hasReadableRecords {
                Text("No readable measurements")
            }
        case .failed(let failure):
            Text(failure.message)
            if history.hasReadableRecords {
                earlierMeasurementsNotice
            }
        }
    }

    private var earlierMeasurementsNotice: some View {
        Text("Showing measurements from earlier checks.")
            .foregroundStyle(.secondary)
    }
}

extension HealthMeasurementReadFailure {
    var message: LocalizedStringKey {
        switch self {
        case .unavailable: "Apple Health is unavailable on this device."
        case .protectedData: "Health data is protected. Unlock your iPhone and try again."
        case .request: "Couldn’t request Health access. Try again."
        case .read: "Couldn’t read Health measurements. Try again."
        case .persistence: "Couldn’t load or save Health history. Try again."
        }
    }
}

struct HealthMeasurementRow: View {
    let measurement: HealthMeasurement
    var metricTitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let metricTitle {
                Text(metricTitle)
                    .font(.headline)
            }
            HealthMeasurementValue(measurement: measurement)
            let timestamp = Date.FormatStyle.dateTime.year().month(.abbreviated).day().hour().minute()
            Group {
                if measurement.endDate > measurement.startDate {
                    Text("\(measurement.startDate, format: timestamp) – \(measurement.endDate, format: timestamp)")
                } else {
                    Text(measurement.startDate, format: timestamp)
                }
                Text(measurement.source.name)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

struct HealthMeasurementValue: View {
    let measurement: HealthMeasurement

    var body: some View {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
        switch measurement.unit {
        case .beatsPerMinute:
            Text("\(measurement.value, format: format) bpm")
                .accessibilityLabel(Text("\(measurement.value, format: format) beats per minute"))
        case .milliseconds:
            let value = Measurement(value: measurement.value, unit: UnitDuration.milliseconds)
            let number = format.precision(.fractionLength(0...3))
            Text(value, format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: number))
                .accessibilityLabel(
                    Text(value, format: .measurement(width: .wide, usage: .asProvided, numberFormatStyle: number))
                )
        case .sleepStage:
            Text(measurement.value, format: format)
        }
    }
}
