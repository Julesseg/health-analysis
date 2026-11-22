import Foundation

struct AnalysisOutputHistory {
    let outputs: [TemporalAnalysisDataset.Output]
    var healthReadAt: Date? = nil
    var healthReadFailure: HealthMeasurementReadFailure? = nil
    var selectedSourceIdentifier: String? = nil

    @MainActor static func stored(
        _ series: ManualAnalysisSeries, in log: ManualLog, asOf: Date, calendar: Calendar
    ) -> Self {
        guard let first = series.firstDay(in: log),
              let start = calendar.date(from: DateComponents(year: first.year, month: first.month, day: first.day))
        else { return Self(outputs: []) }

        var outputs: [TemporalAnalysisDataset.Output] = []
        var date = calendar.startOfDay(for: start)
        let end = calendar.startOfDay(for: asOf)
        while date < end {
            let day = ManualLogDay(date, timeZone: calendar.timeZone)
            if let sample = series.numericValue(in: log, on: day) {
                outputs.append(.init(
                    date: date, anchor: date, behaviorCutoff: date, value: sample.value,
                    origin: sample.origin, trackingValue: sample.trackingValue
                ))
            }
            guard let next = calendar.dateInterval(of: .day, for: date)?.end, next > date else { break }
            date = next
        }
        return Self(outputs: outputs)
    }
}
