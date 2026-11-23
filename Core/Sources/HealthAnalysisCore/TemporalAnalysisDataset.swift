import Foundation

struct TemporalAnalysisDataset: Sendable {
    struct Output: Sendable {
        let date: Date
        let anchor: Date
        let behaviorCutoff: Date
        let value: Double
        var source: HealthMeasurement.Source? = nil
        var origin: ManualValueOrigin? = nil
        var trackingValue: ManualTrackingValue? = nil
        var importedRecord: AnalysisImportedRecord? = nil
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
                value: record.value, source: record.source,
                importedRecord: .init(source: record.source, start: record.startDate, end: record.endDate)
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
                    value: episode.duration / 3600, source: episode.source,
                    importedRecord: .init(
                        source: episode.source, start: episode.startDate, end: episode.wakeTime,
                        sleepTimeZoneEvidence: episode.timeZoneEvidence
                    )
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

    static func activityOutputs(
        _ workouts: [HealthWorkout], variable: ActivityTrackingVariable, calendar: Calendar
    ) -> [Output] {
        DailyActivityHistory(workouts: workouts, variable: variable, calendar: calendar).days.compactMap { day in
            guard case .observed(let amount) = day.value, let source = day.workouts.first?.source,
                  let start = day.workouts.map(\.startDate).min(), let end = day.workouts.map(\.endDate).max()
            else { return nil }
            return .init(
                date: day.date, anchor: end, behaviorCutoff: calendar.startOfDay(for: start),
                value: amount / (variable == .runningDistance ? 1_000 : 60), source: source,
                importedRecord: .init(source: source, start: start, end: end)
            )
        }
    }

    struct InputWindow {
        let value: AnalysisObservation.Input?
        let missingDates: [Date]
        var excludedCategoryInput: AnalysisInspection.OutputWithoutPair.ExcludedCategoryInput? = nil
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
            asOf: Date, calendar: Calendar, after cutoff: Date? = nil
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
            self.selectedSourceIdentifier = selectedSourceIdentifier
            let cutoffDay = cutoff.map { calendar.startOfDay(for: $0) }
            rows = dailyOutputs.values.sorted { $0.date < $1.date }.compactMap { output in
                if let cutoff, let cutoffDay, output.anchor <= cutoff || output.date <= cutoffDay { return nil }
                var cursor = output.behaviorCutoff
                var dates: [Date] = []
                for _ in 0..<window.dayCount {
                    guard let preceding = calendar.precedingDay(before: cursor) else {
                        return cutoff == nil ? Row(output: output, behaviorDates: []) : nil
                    }
                    dates.append(preceding)
                    cursor = preceding
                }
                if let cutoff, cursor <= cutoff { return nil }
                return Row(output: output, behaviorDates: dates.reversed())
            }
            outputDates = rows.map(\.output.date)
            outputSource = rows.last?.output.source
        }
    }

    let observations: [AnalysisObservation]
    let coverage: AnalysisCoverage
    let outputSource: HealthMeasurement.Source?
    let inspection: AnalysisInspection

    @MainActor init(
        outputs: [Output], selectedSourceIdentifier: String? = nil, inputs: [AnalysisSeriesID],
        manualInputs: [AnalysisSeriesID: ManualAnalysisSeries],
        importedInputs: [AnalysisSeriesID: [Date: AnalysisObservation.Input.Day]], manualLog: ManualLog,
        window: AnalysisBehaviorWindow, history: AnalysisPeriod, asOf: Date, calendar: Calendar,
        categoryInputs: [AnalysisSeriesID: AnalysisCategoryContrast] = [:], after cutoff: Date? = nil
    ) {
        let plan = Plan(
            outputs: outputs, selectedSourceIdentifier: selectedSourceIdentifier,
            window: window, history: history, asOf: asOf, calendar: calendar, after: cutoff
        )
        var dailyInputs: [AnalysisSeriesID: [Date: AnalysisObservation.Input.Day?]] = [:]
        self.init(plan: plan, inputs: inputs, calendar: calendar) { id, row in
            if let contrast = categoryInputs[id], let series = manualInputs[id] {
                return Self.categoryInputWindow(
                    series, contrast: contrast, dates: row.behaviorDates, manualLog: manualLog, timeZone: calendar.timeZone
                )
            }
            return Self.summarizeInput(id, dates: row.behaviorDates) { date in
                if let cached = dailyInputs[id]?[date] { return cached }
                if let imported = importedInputs[id] {
                    guard let input = imported[date] else { return nil }
                    if let cutoff, let record = input.importedRecord, record.start <= cutoff { return nil }
                    return input
                }
                let input = manualInputs[id].flatMap {
                    Self.inputDay(date, for: $0, manualLog: manualLog, timeZone: calendar.timeZone)
                }
                let eligible = cutoff == nil || input?.origin == .observation ? input : nil
                dailyInputs[id, default: [:]][date] = .some(eligible)
                return eligible
            }
        }
    }

    @MainActor static func inputDay(
        _ date: Date, for series: ManualAnalysisSeries, manualLog: ManualLog, timeZone: TimeZone
    ) -> AnalysisObservation.Input.Day? {
        let day = ManualLogDay(date, timeZone: timeZone)
        guard let sample = series.numericValue(in: manualLog, on: day), let value = sample.value else { return nil }
        return .init(date: date, value: value, origin: sample.origin, trackingValue: sample.trackingValue)
    }

    @MainActor private static func categoryInputWindow(
        _ series: ManualAnalysisSeries, contrast: AnalysisCategoryContrast, dates: [Date],
        manualLog: ManualLog, timeZone: TimeZone
    ) -> InputWindow {
        guard dates.count == 1, let date = dates.first else { return .init(value: nil, missingDates: dates) }
        let day = ManualLogDay(date, timeZone: timeZone)
        guard let sample = series.numericValue(in: manualLog, on: day, category: .contrast(contrast)),
              case .category(let category)? = sample.trackingValue else {
            return .init(value: nil, missingDates: [date])
        }
        let id = series.variable.id
        guard let value = sample.value else {
            return .init(value: nil, missingDates: [], excludedCategoryInput: .init(
                series: id, date: date, category: category, origin: sample.origin
            ))
        }
        let entry = AnalysisObservation.Input.Day(
            date: date, value: value, origin: sample.origin, trackingValue: sample.trackingValue
        )
        return .init(value: .init(series: id, date: date, value: value, origin: sample.origin, days: [entry]), missingDates: [])
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
        let value: Double
        if case .health(.restingHeartRate, _) = id {
            value = total / Double(days.count)
        } else {
            value = total
        }
        let input = AnalysisObservation.Input(
            series: id, date: first.date, value: value,
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
            var excluded: [AnalysisInspection.OutputWithoutPair.ExcludedCategoryInput] = []
            for id in inputs {
                let window = inputWindow(id, row)
                if let input = window.value { pairedInputs.append(input) }
                missing += window.missingDates.map { .init(series: id, date: $0) }
                if let category = window.excludedCategoryInput { excluded.append(category) }
            }
            guard pairedInputs.count == inputs.count else {
                unpaired.append(.init(
                    date: row.output.date, anchor: row.output.anchor, value: row.output.value,
                    source: row.output.source, missingInputs: missing, origin: row.output.origin,
                    trackingValue: row.output.trackingValue, excludedCategoryInputs: excluded.isEmpty ? nil : excluded,
                    sleepTimeZoneEvidence: row.output.sleepTimeZoneEvidence, importedRecord: row.output.importedRecord
                ))
                return nil
            }
            return AnalysisObservation(
                outputDate: row.output.date, outputAnchor: row.output.anchor, outputValue: row.output.value, inputs: pairedInputs,
                outputOrigin: row.output.origin, outputTrackingValue: row.output.trackingValue,
                sleepTimeZoneEvidence: row.output.sleepTimeZoneEvidence, importedOutput: row.output.importedRecord
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
