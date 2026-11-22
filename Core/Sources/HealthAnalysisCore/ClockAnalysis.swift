import Foundation

public struct AnalysisClockInterval: Codable, Sendable, Identifiable {
    public var id: AnalysisSeriesID { series }
    public let series: AnalysisSeriesID
    public let startMinute: Int
    public let endMinute: Int

    fileprivate init?(series: AnalysisSeriesID, values: [Double]) {
        let sorted = Set(values.map(Int.init)).sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        var largestGap = first + 1440 - last
        var start = first
        var end = last
        for (before, after) in zip(sorted, sorted.dropFirst()) where after - before > largestGap {
            largestGap = after - before
            start = after
            end = before
        }
        guard largestGap > 720 else { return nil }
        self.series = series
        startMinute = start
        endMinute = end
    }

    public func offset(_ minute: Double) -> Double {
        (minute - Double(startMinute) + 1440).truncatingRemainder(dividingBy: 1440)
    }
}

enum ClockAnalysis {
    static func assess(
        _ rows: [AnalysisObservation], inputs: [AnalysisModeledInput], output: AnalysisSeriesID,
        outputIsClock: Bool, model: AnalysisModel, fit: ([AnalysisObservation]) -> NumericAnalysis
    ) -> (NumericAnalysis, [AnalysisClockInterval]) {
        let clockInputs = inputs.indices.filter { inputs[$0].kind == .tracked(.timeOfDay) }
        let defaultDays = rows.count { row in
            (row.outputOrigin ?? .observation) != .observation || row.inputs.contains { $0.origin != .observation }
        }
        var reasons: [AnalysisEvidence.Reason] = []
        if rows.contains(where: { row in
            row.outputClockPrecision == .approximate ||
                clockInputs.contains { row.inputs[$0].days.first?.clockPrecision == .approximate }
        }) { reasons.append(.approximateClockEntries) }
        if rows.contains(where: {
            if case .importTimeZone? = $0.sleepTimeZoneEvidence { return true }
            return false
        }) { reasons.append(.sleepTimeZoneFallback) }
        var intervals: [AnalysisClockInterval] = []

        func result(_ assessment: NumericAnalysis) -> (NumericAnalysis, [AnalysisClockInterval]) {
            (NumericAnalysis(
                model: assessment.model, estimates: assessment.estimates,
                interaction: assessment.interaction, evidence: AnalysisEvidence(
                    grade: assessment.evidence.grade, reasons: assessment.evidence.reasons + reasons,
                    defaultDayCount: defaultDays, dependenceLagDays: assessment.evidence.dependenceLagDays
                )
            ), intervals)
        }

        let minimumDays = max(42, 12 * (inputs.count + 1))
        func insufficient(_ reason: AnalysisEvidence.Reason) -> (NumericAnalysis, [AnalysisClockInterval]) {
            result(NumericAnalysis(model: model, estimates: [], interaction: nil, evidence: .init(
                grade: .insufficient, reasons: [reason], defaultDayCount: defaultDays, dependenceLagDays: nil
            )))
        }
        guard rows.count >= minimumDays else {
            return insufficient(.inadequateJointCoverage(minimumDays: minimumDays))
        }

        var unsupported: Set<AnalysisSeriesID> = []
        var lowVariation: Set<AnalysisSeriesID> = []
        var shortInputRange: Set<AnalysisSeriesID> = []
        func prepare(
            _ series: AnalysisSeriesID, values: [Double], recorded: [Double], inputIncrement: Double? = nil
        ) -> AnalysisClockInterval? {
            guard let interval = AnalysisClockInterval(series: series, values: values) else {
                unsupported.insert(series)
                return nil
            }
            intervals.append(interval)
            let sorted = recorded.map(interval.offset).sorted()
            if sorted.count < 12 || sorted[3 * sorted.count / 4] - sorted[sorted.count / 4] < 30 {
                lowVariation.insert(series)
            } else if let inputIncrement, let first = sorted.first, let last = sorted.last,
                      last - first < inputIncrement {
                shortInputRange.insert(series)
            }
            return interval
        }

        var inputIntervals: [Int: AnalysisClockInterval] = [:]
        for index in clockInputs {
            let values = rows.map { $0.inputs[index] }
            inputIntervals[index] = prepare(
                inputs[index].series, values: values.map(\.value),
                recorded: values.compactMap { $0.origin == .observation ? $0.value : nil },
                inputIncrement: inputs[index].inputIncrement
            )
        }
        let outputInterval = outputIsClock ? prepare(
            output, values: rows.map(\.outputValue),
            recorded: rows.compactMap { ($0.outputOrigin ?? .observation) == .observation ? $0.outputValue : nil }
        ) : nil
        guard unsupported.isEmpty else { return insufficient(.clockIntervalUnavailable(unsupported)) }
        guard lowVariation.isEmpty else { return insufficient(.limitedRecordedClockVariation(lowVariation)) }
        guard shortInputRange.isEmpty else { return insufficient(.clockIncrementUnavailable(shortInputRange)) }

        let unwrapped = rows.map { row in
            let inputs = row.inputs.enumerated().map { index, input in
                guard let interval = inputIntervals[index] else { return input }
                return AnalysisObservation.Input(
                    series: input.series, date: input.date, value: interval.offset(input.value),
                    origin: input.origin, days: input.days
                )
            }
            return AnalysisObservation(
                outputDate: row.outputDate, outputAnchor: row.outputAnchor,
                outputValue: outputInterval?.offset(row.outputValue) ?? row.outputValue,
                inputs: inputs, outputOrigin: row.outputOrigin, outputTrackingValue: row.outputTrackingValue
            )
        }
        reasons.append(.clockModelLimitations)
        return result(fit(unwrapped))
    }
}
