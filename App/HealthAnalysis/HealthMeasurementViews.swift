import HealthAnalysisCore
import SwiftUI

struct HealthMeasurementsSection: View {
    let history: HealthMeasurementHistory

    var body: some View {
        Section("Health measurements") {
            HealthReadStatus(history: history)
            NavigationLink("Resting heart rate") {
                HealthMeasurementHistoryView(history: history)
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
                HealthMeasurementRow(measurement: measurement, showsMetric: true)
            }
        }
    }
}

struct HealthReadStatus: View {
    let history: HealthMeasurementHistory
    var showsInitialState = true

    var body: some View {
        switch history.readState {
        case .idle:
            if showsInitialState {
                Text("No readable measurements")
            }
        case .loading:
            ProgressView("Checking Health measurements…")
                .accessibilityIdentifier("health.readProgress")
        case .loaded(let readableCount):
            if readableCount == 0 {
                Text("No readable measurements")
                if !history.history.isEmpty {
                    earlierMeasurementsNotice
                }
            } else if readableCount < history.history.count {
                Text("Some measurements are from earlier checks.")
                    .foregroundStyle(.secondary)
            }
        case .failed(let failure):
            Text(message(for: failure))
            if !history.history.isEmpty {
                earlierMeasurementsNotice
            }
        }
    }

    private var earlierMeasurementsNotice: some View {
        Text("Showing measurements from earlier checks.")
            .foregroundStyle(.secondary)
    }

    private func message(for failure: HealthMeasurementReadFailure) -> LocalizedStringKey {
        switch failure {
        case .unavailable: "Apple Health is unavailable on this device."
        case .protectedData: "Health data is protected. Unlock your iPhone and try again."
        case .request: "Couldn’t request Health access. Try again."
        case .read: "Couldn’t read Health measurements. Try again."
        }
    }
}

struct HealthMeasurementRow: View {
    let measurement: HealthMeasurement
    var showsMetric = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsMetric {
                Text("Resting heart rate")
                    .font(.headline)
            }
            let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
            Text("\(measurement.value, format: format) bpm")
                .accessibilityLabel(Text("\(measurement.value, format: format) beats per minute"))
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
