import Foundation

struct TemporalAnalysisDataset {
    struct Output: Sendable {
        let date: Date
        let anchor: Date
        let behaviorCutoff: Date
        let value: Double
        var source: HealthMeasurement.Source? = nil
        var origin: ManualValueOrigin? = nil
        var trackingValue: ManualTrackingValue? = nil
        var sleepTimeZoneEvidence: SleepEpisode.TimeZoneEvidence? = nil
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

    static func sleepOutputs(
        _ episodes: [SleepEpisode], asOf: Date, calendar: Calendar, timing: SleepTiming? = nil
    ) -> [Output] {
        episodes.filter { $0.wakeTime <= asOf && $0.duration.isFinite && $0.duration > 0 }.sorted {
            (-$0.duration, $0.startDate, $0.wakeTime) < (-$1.duration, $1.startDate, $1.wakeTime)
        }.compactMap { episode in
            guard let wakeLabel = calendar.date(from: episode.wakeDay),
                  calendar.dateComponents([.year, .month, .day], from: wakeLabel) == episode.wakeDay else { return nil }
            let date = calendar.startOfDay(for: wakeLabel)
            let onsetDayInAnalysisZone = calendar.startOfDay(for: episode.startDate)
            guard let timing else {
                return Output(
                    date: date, anchor: episode.wakeTime, behaviorCutoff: min(date, onsetDayInAnalysisZone),
                    value: episode.duration / 3600, source: episode.source
                )
            }

            let onsetZone = TimeZone(identifier: episode.onsetTimeZoneEvidence.identifier) ?? episode.timeZone
            let evidence = timing == .onset ? episode.onsetTimeZoneEvidence : episode.timeZoneEvidence
            let anchor = timing == .onset ? episode.startDate : episode.wakeTime
            let eventZone = timing == .onset ? onsetZone : episode.timeZone
            let clock = calendar.dateComponents(in: eventZone, from: anchor)

            var onsetCalendar = calendar
            onsetCalendar.timeZone = onsetZone
            let onsetDay = onsetCalendar.dateComponents([.year, .month, .day], from: episode.startDate)
            guard let localOnsetLabel = calendar.date(from: onsetDay),
                  calendar.dateComponents([.year, .month, .day], from: localOnsetLabel) == onsetDay,
                  let hour = clock.hour, let minute = clock.minute else { return nil }
            return Output(
                date: date, anchor: anchor,
                behaviorCutoff: min(date, onsetDayInAnalysisZone, calendar.startOfDay(for: localOnsetLabel)),
                value: Double(hour * 60 + minute), source: episode.source, sleepTimeZoneEvidence: evidence
            )
        }
    }

    struct InputWindow {
        let value: AnalysisObservation.Input?
        let missingDates: [Date]
    }

    struct Plan: Sendable {
        struct Row: Sendable {
            let output: Output
            let behaviorDates: [Date]
        }

        let outputDates: [Date]
        let rows: [Row]
        let outputSource: HealthMeasurement.Source?
        let selectedSourceIdentifier: String?

        init(
            outputs: [Output], selectedSourceIdentifier: String? = nil, window: AnalysisBehaviorWindow, history: AnalysisPeriod,
            asOf: Date, calendar: Calendar
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
            let outputDates = dailyOutputs.keys.sorted()
            self.outputDates = outputDates
            self.selectedSourceIdentifier = selectedSourceIdentifier
            outputSource = outputDates.last.flatMap { dailyOutputs[$0]?.source }
            rows = outputDates.compactMap { date in
                guard let output = dailyOutputs[date] else { return nil }
                var cursor = output.behaviorCutoff
                var dates: [Date] = []
                for _ in 0..<window.dayCount {
                    guard let preceding = calendar.precedingDay(before: cursor) else {
                        return Row(output: output, behaviorDates: [])
                    }
                    dates.append(preceding)
                    cursor = preceding
                }
                return Row(output: output, behaviorDates: dates.reversed())
            }
        }
    }

    let observations: [AnalysisObservation]
    let coverage: AnalysisCoverage
    let outputSource: HealthMeasurement.Source?
    let inspection: AnalysisInspection

    @MainActor init(
        outputs: [Output], selectedSourceIdentifier: String? = nil, inputs: [ManualAnalysisSeries], manualLog: ManualLog,
        window: AnalysisBehaviorWindow, history: AnalysisPeriod, asOf: Date, calendar: Calendar
    ) {
        let plan = Plan(
            outputs: outputs, selectedSourceIdentifier: selectedSourceIdentifier,
            window: window, history: history, asOf: asOf, calendar: calendar
        )
        var dailyInputs: [AnalysisSeriesID: [Date: AnalysisObservation.Input.Day?]] = [:]
        let catalog = Dictionary(uniqueKeysWithValues: inputs.map { ($0.variable.id, $0) })
        self.init(plan: plan, inputs: inputs.map(\.variable.id), calendar: calendar) { id, row in
            Self.summarizeInput(id, dates: row.behaviorDates) { date in
                if let cached = dailyInputs[id]?[date] { return cached }
                let input = catalog[id].flatMap {
                    Self.inputDay(date, for: $0, manualLog: manualLog, timeZone: calendar.timeZone)
                }
                dailyInputs[id, default: [:]][date] = .some(input)
                return input
            }
        }
    }

    @MainActor static func inputDay(
        _ date: Date, for series: ManualAnalysisSeries, manualLog: ManualLog, timeZone: TimeZone
    ) -> AnalysisObservation.Input.Day? {
        let day = ManualLogDay(date, timeZone: timeZone)
        return series.numericValue(in: manualLog, on: day).map { sample in
            AnalysisObservation.Input.Day(
                date: date, value: sample.value, origin: sample.origin, trackingValue: sample.trackingValue
            )
        }
    }

    static func summarizeInput(
        _ id: AnalysisSeriesID, dates: [Date],
        inputDay: (Date) -> AnalysisObservation.Input.Day?
    ) -> InputWindow {
        var missingDates: [Date] = []
        let days = dates.compactMap { date -> AnalysisObservation.Input.Day? in
            if let day = inputDay(date) { return day }
            missingDates.append(date)
            return nil
        }
        guard let first = days.first, missingDates.isEmpty else {
            return InputWindow(value: nil, missingDates: missingDates)
        }
        let total = days.reduce(0) { $0 + $1.value }
        guard total.isFinite else { return InputWindow(value: nil, missingDates: []) }
        let input = AnalysisObservation.Input(
            series: id, date: first.date, value: total,
            origin: days.first { $0.origin != .observation }?.origin ?? .observation, days: days
        )
        return InputWindow(value: input, missingDates: [])
    }

    init(
        plan: Plan, inputs: [AnalysisSeriesID], calendar: Calendar,
        inputWindow: (AnalysisSeriesID, Plan.Row) -> InputWindow
    ) {
        var unpaired: [AnalysisInspection.OutputWithoutPair] = []
        observations = plan.rows.compactMap { row -> AnalysisObservation? in
            var pairedInputs: [AnalysisObservation.Input] = []
            var missing: [AnalysisInspection.OutputWithoutPair.MissingInput] = []
            for id in inputs {
                let window = inputWindow(id, row)
                if let input = window.value { pairedInputs.append(input) }
                missing += window.missingDates.map { .init(series: id, date: $0) }
            }
            guard pairedInputs.count == inputs.count else {
                unpaired.append(.init(
                    date: row.output.date, anchor: row.output.anchor, value: row.output.value,
                    source: row.output.source, missingInputs: missing, origin: row.output.origin,
                    trackingValue: row.output.trackingValue, sleepTimeZoneEvidence: row.output.sleepTimeZoneEvidence
                ))
                return nil
            }
            return AnalysisObservation(
                outputDate: row.output.date, outputAnchor: row.output.anchor, outputValue: row.output.value, inputs: pairedInputs,
                outputOrigin: row.output.origin, outputTrackingValue: row.output.trackingValue,
                sleepTimeZoneEvidence: row.output.sleepTimeZoneEvidence
            )
        }
        coverage = AnalysisCoverage(observations: observations, outputDates: plan.outputDates, calendar: calendar)
        outputSource = plan.outputSource
        inspection = AnalysisInspection(unpairedOutputs: unpaired, selectedOutputSourceIdentifier: plan.selectedSourceIdentifier)
    }
}

extension Calendar {
    fileprivate func precedingDay(before dayStart: Date) -> Date? {
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
