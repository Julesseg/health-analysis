import Foundation

struct AnalysisOutputHistory {
    let outputs: [TemporalAnalysisDataset.Output]
    var healthReadAt: Date? = nil
    var healthReadFailure: HealthMeasurementReadFailure? = nil
    var selectedSourceIdentifier: String? = nil

    func inputDays(calendar: Calendar) -> [Date: AnalysisObservation.Input.Day] {
        var days: [Date: AnalysisObservation.Input.Day] = [:]
        for output in outputs {
            guard days[output.date] == nil, let record = output.importedRecord,
                  let interval = calendar.dateInterval(of: .day, for: output.date),
                  record.end <= interval.end else { continue }
            days[output.date] = .init(date: output.date, value: output.value, origin: .observation, importedRecord: record)
        }
        return days
    }

    @MainActor static func stored(
        _ series: ManualAnalysisSeries, in log: ManualLog, asOf: Date, calendar: Calendar,
        categoryEvent: TrackingCategory.ID? = nil
    ) -> Self {
        guard let first = series.firstDay(in: log),
              let start = calendar.date(from: DateComponents(year: first.year, month: first.month, day: first.day))
        else { return Self(outputs: []) }

        var outputs: [TemporalAnalysisDataset.Output] = []
        var date = calendar.startOfDay(for: start)
        let end = calendar.startOfDay(for: asOf)
        while date < end {
            let day = ManualLogDay(date, timeZone: calendar.timeZone)
            if let sample = series.numericValue(in: log, on: day, category: categoryEvent.map(CategoryAnalysis.Transform.event)),
               let value = sample.value {
                outputs.append(.init(
                    date: date, anchor: date, behaviorCutoff: date, value: value,
                    origin: sample.origin, trackingValue: sample.trackingValue
                ))
            }
            guard let next = calendar.dateInterval(of: .day, for: date)?.end, next > date else { break }
            date = next
        }
        return Self(outputs: outputs)
    }
}
