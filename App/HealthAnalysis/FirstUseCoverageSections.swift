import HealthAnalysisCore
import SwiftUI

struct FirstUseCoverageSections: View {
    let history: HealthMeasurementHistory
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        Section("Readable measurements") {
            ForEach(HealthMetricPresentation.supported) { presentation in
                coverageRow(presentation.title) {
                    if let coverage = history.coverage(for: presentation.metric, calendar: calendar) {
                        measurementCoverage(coverage)
                    } else if presentation.metric == .sleepAnalysis {
                        SleepHistoryUnavailable(
                            hasRecords: !history.measurements(for: .sleepAnalysis).isEmpty,
                            hasSelectedSource: history.preferredSource(for: .sleepAnalysis) != nil
                        )
                    } else if history.preferredSource(for: presentation.metric) != nil {
                        Text("No imported measurements for this source.")
                    } else {
                        Text("No readable measurements")
                    }
                }
                .accessibilityIdentifier("firstUse.coverage.\(presentation.metric.rawValue)")
            }
        }
        Section("Heart rate variability") {
            ForEach(HRVSeries.StoredType.allCases, id: \.self) { type in
                let series = history.hrvSeries(for: type, calendar: calendar)
                if series.isEmpty {
                    coverageRow(type.storageLabel) { Text("No readable measurements") }
                }
                ForEach(series, id: \.source.bundleIdentifier) { item in
                    coverageRow(type.storageLabel) {
                        Text(verbatim: item.source.name)
                        measurementCoverage(item.coverage)
                    }
                }
            }
            Text(HRVSeries.AnalysisLimitation.unverifiedOriginalMeasureAndSummary.message)
                .foregroundStyle(.secondary)
        }
        Section("Activity") {
            ForEach(ActivityTrackingVariable.allCases) { variable in
                coverageRow(variable.title) {
                    if let coverage = history.activityHistory(for: variable, calendar: calendar).coverage {
                        dateRange(from: coverage.firstRecordedDay, through: coverage.latestRecordedDay)
                        LabeledContent("Days with a total", value: coverage.daysWithValues.formatted())
                        LabeledContent("Days without workout records in this range", value: coverage.daysWithoutWorkouts.formatted())
                    } else {
                        Text("No readable workout records")
                    }
                }
            }
        }
    }

    private func coverageRow<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder details: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            details()
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func measurementCoverage(_ coverage: HealthMeasurementHistory.Coverage) -> some View {
        Group {
            dateRange(
                from: coverage.firstMeasurement, through: coverage.latestMeasurement,
                firstZone: coverage.firstMeasurementTimeZone, lastZone: coverage.latestMeasurementTimeZone
            )
            LabeledContent("Days with measurements", value: coverage.measuredDays.formatted())
            LabeledContent("Days without measurements in this range", value: coverage.daysWithoutMeasurements.formatted())
        }
    }

    private func dateRange(
        from first: Date, through last: Date, firstZone: TimeZone? = nil, lastZone: TimeZone? = nil
    ) -> Text {
        let start = first.formatted(dateFormat(in: firstZone))
        let end = last.formatted(dateFormat(in: lastZone))
        if start == end { return Text(verbatim: start) }
        return Text("\(start) – \(end)")
    }

    private func dateFormat(in timeZone: TimeZone?) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.year().month(.abbreviated).day().locale(locale)
        format.calendar = calendar
        format.timeZone = timeZone ?? calendar.timeZone
        return format
    }
}
