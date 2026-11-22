import Foundation

enum CategoryEventAnalysis {
    static func assess(
        _ observations: [AnalysisObservation], inputs: [AnalysisModeledInput],
        coverage: AnalysisCoverage, categoryEvidence: AnalysisCategoryEvidence, calendar: Calendar
    ) -> NumericAnalysis {
        let count = observations.count
        let defaultDays = observations.count { row in
            row.outputOrigin != .observation || row.inputs.contains { $0.origin != .observation }
        }
        func result(
            _ grade: AnalysisEvidence.Grade, _ reasons: [AnalysisEvidence.Reason],
            estimates: [AnalysisEstimate] = [], lagDays: Int? = nil
        ) -> NumericAnalysis {
            NumericAnalysis(
                model: .categoryEventLogisticV1, estimates: estimates, interaction: nil, evidence: AnalysisEvidence(
                    grade: grade, reasons: reasons, defaultDayCount: defaultDays, dependenceLagDays: lagDays
                )
            )
        }

        let parameterCount = inputs.count + 1
        let minimumDays = max(42, 12 * parameterCount)
        guard count >= minimumDays else {
            return result(.insufficient, [.inadequateJointCoverage(minimumDays: minimumDays)])
        }
        let recordedOutputs = observations.filter { $0.outputOrigin == .observation }
        let recordedEvents = recordedOutputs.count { $0.outputValue == 1 }
        let minimumClassDays = max(CategoryAnalysis.minimumRecordedDaysPerLevel, 4 * parameterCount)
        guard min(recordedEvents, recordedOutputs.count - recordedEvents) >= minimumClassDays else {
            return result(.insufficient, [.sparseCategoryOutput(minimumRecordedDays: minimumClassDays)])
        }
        let sparseConditions = Set(categoryEvidence.inputLevels.filter { _, levels in
            levels.contains { level in
                guard let support = level.eventSupport else { return true }
                return min(support.eventDayCount, support.otherDayCount) < CategoryAnalysis.minimumRecordedDaysPerLevel
            }
        }.keys)
        guard sparseConditions.isEmpty else {
            return result(.insufficient, [.sparseCategoryEventByInput(sparseConditions)])
        }

        guard let columns = NumericAnalysis.inputColumns(observations, inputs: inputs) else {
            return result(.insufficient, [.uncertaintyUnavailable])
        }
        var reasons = NumericAnalysis.inputLimitations(observations, inputs: inputs, columns: columns)
        guard reasons.isEmpty else { return result(.insufficient, reasons) }

        func collinear(_ indices: Set<Int>) -> NumericAnalysis {
            result(.insufficient, [.collinearInputs(Set(indices.map { inputs[$0].series }))])
        }
        do {
            let inflation = try OrthogonalDesign(columns: columns).varianceInflation
            let dependent = Set(inflation.indices.filter { inflation[$0] >= 20 })
            guard dependent.isEmpty else { return collinear(dependent) }
        } catch .dependentColumns(let indices) {
            return collinear(indices)
        } catch {
            return result(.insufficient, [.categoryEventModelUnavailable])
        }
        let dayNumbers = observations.compactMap { calendar.ordinality(of: .day, in: .era, for: $0.outputDate) }
        let lagDays = CalendarHAC.defaultLagDays(for: count)
        guard let fit = BinaryEventFit(columns: columns, events: observations.map(\.outputValue)) else {
            return result(.insufficient, [.categoryEventModelUnavailable])
        }

        var estimates: [AnalysisEstimate] = []
        for (index, input) in inputs.enumerated() {
            var contrast = Array(repeating: 0.0, count: inputs.count)
            contrast[index] = input.inputIncrement
            guard let log = fit.logOddsContrast(contrast, dayNumbers: dayNumbers, lagDays: lagDays),
                  log.estimate + log.halfWidth < 700 else {
                return result(.insufficient, [.uncertaintyUnavailable])
            }
            let interval = expm1(log.estimate - log.halfWidth)...expm1(log.estimate + log.halfWidth)
            estimates.append(AnalysisEstimate(
                input: input.series, inputIncrement: input.inputIncrement, difference: expm1(log.estimate),
                interval: interval, finding: NumericAnalysis.finding(interval, nearZero: nil),
                scale: .proportionalCategoryOddsChange
            ))
        }
        reasons.append(.categoryEventModelLimitations)
        if inputs.contains(where: { $0.kind?.ratingThreshold != nil }) { reasons.append(.ratingThresholdLimitations) }
        if count < 90 { reasons.append(.limitedHistory) }
        if Double(count) / Double(count + coverage.missingDays) < 0.75 { reasons.append(.sparseCoverage) }
        if Double(defaultDays) / Double(count) > 0.25 { reasons.append(.manyDefaults) }
        if estimates.contains(where: { $0.finding == .uncertain }) { reasons.append(.indeterminateInterval) }
        return result(.low, reasons, estimates: estimates, lagDays: lagDays)
    }
}
