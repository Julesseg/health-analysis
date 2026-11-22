import Foundation

struct AnalysisOutputHistory {
    struct Day {
        let anchor: Date
        let value: Double
        var origin: ManualValueOrigin? = nil
        var trackingValue: ManualTrackingValue? = nil
        var source: HealthMeasurement.Source? = nil
    }

    let days: [Date: Day]
    var healthReadAt: Date? = nil
    var healthReadFailure: HealthMeasurementReadFailure? = nil

    static func restingHeartRate(
        _ records: [HealthMeasurement], readAt: Date?, failure: HealthMeasurementReadFailure?, calendar: Calendar
    ) -> Self {
        var dailyOutputs: [Date: HealthMeasurement] = [:]
        for record in records {
            let date = calendar.startOfDay(for: record.startDate)
            if let existing = dailyOutputs[date],
               (existing.startDate, existing.endDate, existing.id.uuidString)
                <= (record.startDate, record.endDate, record.id.uuidString) {
                continue
            }
            dailyOutputs[date] = record
        }
        return Self(days: dailyOutputs.mapValues {
            Day(anchor: $0.startDate, value: $0.value, source: $0.source)
        }, healthReadAt: readAt, healthReadFailure: failure)
    }

    @MainActor static func stored(
        _ series: ManualAnalysisSeries, in log: ManualLog, asOf: Date, calendar: Calendar
    ) -> Self {
        guard let first = series.firstDay(in: log),
              let start = calendar.date(from: DateComponents(year: first.year, month: first.month, day: first.day))
        else { return Self(days: [:]) }

        var days: [Date: Day] = [:]
        var date = calendar.startOfDay(for: start)
        let end = calendar.startOfDay(for: asOf)
        while date < end {
            let day = ManualLogDay(date, timeZone: calendar.timeZone)
            if let sample = series.numericValue(in: log, on: day) {
                days[date] = Day(anchor: date, value: sample.value, origin: sample.origin, trackingValue: sample.trackingValue)
            }
            guard let next = calendar.dateInterval(of: .day, for: date)?.end, next > date else { break }
            date = next
        }
        return Self(days: days)
    }
}
