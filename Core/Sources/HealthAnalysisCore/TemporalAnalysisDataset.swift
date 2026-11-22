import Foundation

struct TemporalAnalysisDataset {
    struct Output {
        let date: Date
        let anchor: Date
        let behaviorCutoff: Date
        let value: Double
        let source: HealthMeasurement.Source
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
    let inspection: AnalysisInspection

    @MainActor init(
        outputs: [Output], selectedSourceIdentifier: String? = nil, quantities: [TrackingQuantity], manualLog: ManualLog,
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

        var dailyInputs: [UUID: [Date: AnalysisObservation.Input.Day?]] = [:]
        func inputDay(_ date: Date, for quantity: TrackingQuantity) -> AnalysisObservation.Input.Day? {
            if let cached = dailyInputs[quantity.id]?[date] { return cached }
            let day = ManualLogDay(date, timeZone: calendar.timeZone)
            let input: AnalysisObservation.Input.Day? = manualLog.analysisValue(for: quantity, on: day).flatMap { amount, origin in
                let value = NSDecimalNumber(decimal: amount).doubleValue
                guard value.isFinite, quantity.unit.lowercased() != "mg" || value >= 0 else { return nil }
                return AnalysisObservation.Input.Day(date: date, value: value, origin: origin)
            }
            dailyInputs[quantity.id, default: [:]][date] = .some(input)
            return input
        }

        let outputDates = dailyOutputs.keys.sorted()
        var unpaired: [AnalysisInspection.OutputWithoutPair] = []
        observations = outputDates.compactMap { date -> AnalysisObservation? in
            guard let output = dailyOutputs[date] else { return nil }
            func recordUnpaired(_ missing: [AnalysisInspection.OutputWithoutPair.MissingInput]) {
                unpaired.append(.init(
                    date: date, anchor: output.anchor, value: output.value, source: output.source, missingInputs: missing
                ))
            }
            var cursor = output.behaviorCutoff
            var behaviorDates: [Date] = []
            for _ in 0..<window.dayCount {
                guard let preceding = calendar.precedingDay(before: cursor) else {
                    recordUnpaired([])
                    return nil
                }
                behaviorDates.append(preceding)
                cursor = preceding
            }
            let dates = behaviorDates.reversed()
            var missing: [AnalysisInspection.OutputWithoutPair.MissingInput] = []
            var inputs: [AnalysisObservation.Input] = []
            for quantity in quantities {
                let series = AnalysisSeriesID.manualQuantity(quantity.id)
                let days = dates.compactMap { date -> AnalysisObservation.Input.Day? in
                    if let day = inputDay(date, for: quantity) { return day }
                    missing.append(.init(series: series, date: date))
                    return nil
                }
                guard days.count == dates.count else { continue }
                let total = days.reduce(0) { $0 + $1.value }
                guard total.isFinite else { continue }
                inputs.append(.init(
                    series: series, date: cursor, value: total,
                    origin: days.first { $0.origin != .observation }?.origin ?? .observation, days: days
                ))
            }
            guard inputs.count == quantities.count else {
                recordUnpaired(missing)
                return nil
            }
            return AnalysisObservation(
                outputDate: date, outputAnchor: output.anchor, outputValue: output.value, inputs: inputs
            )
        }
        coverage = AnalysisCoverage(observations: observations, outputDates: outputDates, calendar: calendar)
        outputSource = outputDates.last.flatMap { dailyOutputs[$0]?.source }
        inspection = AnalysisInspection(unpairedOutputs: unpaired, selectedOutputSourceIdentifier: selectedSourceIdentifier)
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
