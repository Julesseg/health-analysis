import Foundation

struct TemporalAnalysisDataset {
    struct Output {
        let date: Date
        let anchor: Date
        let behaviorCutoff: Date
        let value: Double
        var source: HealthMeasurement.Source? = nil
        var origin: ManualValueOrigin? = nil
        var trackingValue: ManualTrackingValue? = nil
    }

    static func restingHeartRateOutputs(
        _ records: [HealthMeasurement], asOf: Date, calendar: Calendar
    ) -> [Output] {
        records.filter {
            $0.metric == .restingHeartRate && $0.unit == .beatsPerMinute && $0.value.isFinite && $0.value > 0
                && $0.startDate <= $0.endDate && $0.endDate <= asOf
        }.sorted {
            ($0.startDate, $0.endDate, $0.id.uuidString) < ($1.startDate, $1.endDate, $1.id.uuidString)
        }.map { record in
            let date = calendar.startOfDay(for: record.startDate)
            return Output(
                date: date, anchor: record.startDate, behaviorCutoff: date,
                value: record.value, source: record.source
            )
        }
    }

    static func sleepDurationOutputs(_ episodes: [SleepEpisode], asOf: Date, calendar: Calendar) -> [Output] {
        episodes.filter { $0.wakeTime <= asOf && $0.duration.isFinite && $0.duration > 0 }.sorted {
            (-$0.duration, $0.startDate, $0.wakeTime) < (-$1.duration, $1.startDate, $1.wakeTime)
        }.compactMap { episode in
            guard let wakeLabel = calendar.date(from: episode.wakeDay),
                  calendar.dateComponents([.year, .month, .day], from: wakeLabel) == episode.wakeDay else { return nil }
            let date = calendar.startOfDay(for: wakeLabel)
            return Output(
                date: date, anchor: episode.wakeTime,
                behaviorCutoff: min(date, calendar.startOfDay(for: episode.startDate)),
                value: episode.duration / 3600, source: episode.source
            )
        }
    }

    let observations: [AnalysisObservation]
    let coverage: AnalysisCoverage
    let outputSource: HealthMeasurement.Source?

    @MainActor init(
        outputs: [Output], inputs: [ManualAnalysisSeries], manualLog: ManualLog,
        window: AnalysisBehaviorWindow, history: AnalysisPeriod, asOf: Date, calendar: Calendar
    ) {
        var dailyOutputs: [Date: Output] = [:]
        let historyEnd = calendar.startOfDay(for: asOf)
        let historyStart = history.dayCount.flatMap {
            calendar.day(byGoingBack: $0 - 1, from: historyEnd)
        }
        for output in outputs {
            if let historyStart, !(historyStart...historyEnd).contains(output.date) { continue }
            if dailyOutputs[output.date] == nil { dailyOutputs[output.date] = output }
        }

        var dailyInputs: [AnalysisSeriesID: [Date: AnalysisObservation.Input.Day?]] = [:]
        func inputDay(_ date: Date, for series: ManualAnalysisSeries) -> AnalysisObservation.Input.Day? {
            let id = series.variable.id
            if let cached = dailyInputs[id]?[date] { return cached }
            let day = ManualLogDay(date, timeZone: calendar.timeZone)
            let input = series.numericValue(in: manualLog, on: day).map { sample in
                AnalysisObservation.Input.Day(
                    date: date, value: sample.value, origin: sample.origin, trackingValue: sample.trackingValue
                )
            }
            dailyInputs[id, default: [:]][date] = .some(input)
            return input
        }

        let outputDates = dailyOutputs.keys.sorted()
        observations = outputDates.compactMap { date -> AnalysisObservation? in
            guard let output = dailyOutputs[date] else { return nil }
            var cursor = output.behaviorCutoff
            var behaviorDates: [Date] = []
            for _ in 0..<window.dayCount {
                guard let preceding = calendar.precedingDay(before: cursor) else { return nil }
                behaviorDates.append(preceding)
                cursor = preceding
            }
            let dates = behaviorDates.reversed()
            var pairedInputs: [AnalysisObservation.Input] = []
            for input in inputs {
                let days = dates.compactMap { inputDay($0, for: input) }
                guard days.count == dates.count else { return nil }
                let total = days.reduce(0) { $0 + $1.value }
                guard total.isFinite else { return nil }
                pairedInputs.append(.init(
                    series: input.variable.id, date: cursor, value: total,
                    origin: days.first { $0.origin != .observation }?.origin ?? .observation, days: days
                ))
            }
            return AnalysisObservation(
                outputDate: date, outputAnchor: output.anchor, outputValue: output.value, inputs: pairedInputs,
                outputOrigin: output.origin, outputTrackingValue: output.trackingValue
            )
        }
        coverage = AnalysisCoverage(observations: observations, outputDates: outputDates, calendar: calendar)
        outputSource = outputDates.last.flatMap { dailyOutputs[$0]?.source }
    }
}

private extension Calendar {
    func precedingDay(before dayStart: Date) -> Date? {
        dateInterval(of: .day, for: dayStart.addingTimeInterval(-1))?.start
    }

    func day(byGoingBack count: Int, from dayStart: Date) -> Date? {
        var day = dayStart
        for _ in 0..<count {
            guard let previous = precedingDay(before: day) else { return nil }
            day = previous
        }
        return day
    }
}
