import Foundation

struct DiscoverySearch: Sendable {
    static let maximumInputs = 4
    static let historyDays = 365
    private static let maximumFindings = 5
    static let familyThreshold = 0.05

    struct OutputPlan: Sendable {
        let output: AnalysisSeriesID
        let metric: HealthMeasurement.Metric
        let window: AnalysisBehaviorWindow
        let plan: TemporalAnalysisDataset.Plan
    }

    private struct Question {
        let configuration: AnalysisConfiguration
        let inputs: [AnalysisVariable]
        let contrast: DiscoverySelection.Contrast
    }

    private struct Evaluation {
        let configuration: AnalysisConfiguration
        let contrast: DiscoverySelection.Contrast
        let assessment: Assessment
    }

    private enum Assessment {
        case modelInsufficient([AnalysisEvidence.Reason])
        case insufficientBlocks
        case tested(pValue: Double, result: AnalysisResult?)
    }

    let cutoff: Date
    let calendar: Calendar
    let startOfHistory: Date
    let inputs: [AnalysisVariable]
    let plans: [OutputPlan]
    let dailyInputs: [AnalysisSeriesID: [Date: AnalysisObservation.Input.Day]]
    let lastReadAt: Date?
    let omittedInputCount: Int

    func evaluate() -> DiscoveryReport? {
        var evaluations: [Evaluation] = []
        for plan in plans {
            guard !Task.isCancelled else { return nil }
            let windows = inputWindows(in: plan.plan)
            for question in questions(for: plan) {
                guard !Task.isCancelled else { return nil }
                evaluations.append(Evaluation(
                    configuration: question.configuration, contrast: question.contrast,
                    assessment: assess(question, in: plan, windows: windows)
                ))
            }
        }
        guard !Task.isCancelled else { return nil }
        let tested = evaluations.enumerated().compactMap { index, evaluation -> (Int, Double)? in
            if case .tested(let pValue, _) = evaluation.assessment { return (index, pValue) }
            return nil
        }.sorted { ($0.1, $0.0) < ($1.1, $1.0) }
        var adjusted: [Int: Double] = [:]
        var runningMaximum = 0.0
        for (rank, (index, pValue)) in tested.enumerated() {
            runningMaximum = max(runningMaximum, min(1, Double(evaluations.count - rank) * pValue))
            adjusted[index] = runningMaximum
        }

        let candidates = evaluations.enumerated().map { index, evaluation in
            let outcome: DiscoveryCandidate.Outcome
            switch evaluation.assessment {
            case .modelInsufficient(let reasons): outcome = .modelInsufficient(reasons)
            case .insufficientBlocks: outcome = .insufficientBlockEvidence
            case .tested: outcome = .tested(adjustedPValue: adjusted[index] ?? 1)
            }
            return DiscoveryCandidate(configuration: evaluation.configuration, contrast: evaluation.contrast, outcome: outcome)
        }
        var findings: [DiscoveryFinding] = []
        for (index, _) in tested {
            guard let adjustedPValue = adjusted[index], adjustedPValue <= Self.familyThreshold,
                  findings.count < Self.maximumFindings else { break }
            let evaluation = evaluations[index]
            guard case .tested(_, let result?) = evaluation.assessment else { continue }
            findings.append(DiscoveryFinding(completed: CompletedAnalysis(
                result: result, updatedAt: cutoff, discovery: DiscoverySelection(
                    methodVersion: 1, cutoff: cutoff, contrast: evaluation.contrast,
                    familySize: candidates.count, adjustedPValue: adjustedPValue
                )
            )))
        }

        let status: DiscoveryReport.Status
        if !findings.isEmpty {
            status = .findings
        } else if !tested.isEmpty {
            status = .noFindings
        } else if evaluations.contains(where: { if case .insufficientBlocks = $0.assessment { true } else { false } }) {
            status = .insufficientBlockEvidence
        } else {
            status = .insufficientModelEvidence
        }
        return DiscoveryReport(
            cutoff: cutoff, status: status, candidates: candidates, findings: findings, omittedInputCount: omittedInputCount
        )
    }

    private func questions(for plan: OutputPlan) -> [Question] {
        func question(
            _ inputs: [AnalysisVariable], adjusting adjustment: [AnalysisVariable] = [], interaction: AnalysisInteraction? = nil
        ) -> Question {
            let series = inputs.map(\.id)
            return Question(
                configuration: AnalysisConfiguration(
                    output: plan.output, inputs: series, adjustmentInputs: adjustment.map(\.id),
                    interaction: interaction, behaviorWindow: plan.window, history: .last365Days, timeZone: calendar.timeZone
                ),
                inputs: inputs + adjustment,
                contrast: interaction.map { .interaction($0) } ?? .input(series[0])
            )
        }

        var questions = inputs.map { question([$0]) }
        for (index, focal) in inputs.enumerated() {
            questions += inputs.filter { $0.id != focal.id }.map { question([focal], adjusting: [$0]) }
            questions += inputs.dropFirst(index + 1).map { moderator in
                question([focal, moderator], interaction: AnalysisInteraction(
                    focal: focal.id, moderator: moderator.id
                ))
            }
        }
        return questions
    }

    private func inputWindows(in plan: TemporalAnalysisDataset.Plan) -> [AnalysisSeriesID: [Date: TemporalAnalysisDataset.InputWindow]] {
        Dictionary(uniqueKeysWithValues: inputs.map { input in
            let days = dailyInputs[input.id] ?? [:]
            let windows = plan.rows.map { row in
                let window = TemporalAnalysisDataset.summarizeInput(input.id, dates: row.behaviorDates) { days[$0] }
                return (row.output.date, window)
            }
            return (input.id, Dictionary(uniqueKeysWithValues: windows))
        })
    }

    private func assess(
        _ question: Question, in output: OutputPlan,
        windows: [AnalysisSeriesID: [Date: TemporalAnalysisDataset.InputWindow]]
    ) -> Assessment {
        let dataset = TemporalAnalysisDataset(plan: output.plan, inputs: question.inputs.map(\.id), calendar: calendar) {
            id, row in windows[id]?[row.output.date] ?? .init(value: nil, missingDates: [])
        }
        let result = AnalysisResult.assess(
            configuration: question.configuration, dataset: dataset, inputs: question.inputs, calendar: calendar,
            practicalDifference: output.metric == .sleepAnalysis ? 0.25 : 1, lastReadAt: lastReadAt, exploratory: true
        )
        let difference: Double
        let interval: ClosedRange<Double>
        switch question.contrast {
        case .input(let series):
            guard let estimate = result.estimates.first(where: { $0.input == series }) else {
                return .modelInsufficient(result.evidence.reasons)
            }
            (difference, interval) = (estimate.difference, estimate.interval)
        case .interaction:
            guard let estimate = result.interaction else { return .modelInsufficient(result.evidence.reasons) }
            (difference, interval) = (estimate.difference, estimate.interval)
        }
        guard let evidence = DiscoveryBlockEvidence.assess(
            result, startOfHistory: startOfHistory, calendar: calendar
        ) else { return .insufficientBlocks }
        let agrees = evidence.mean.sign == difference.sign && !interval.contains(0)
        return .tested(pValue: evidence.pValue, result: agrees && evidence.pValue <= Self.familyThreshold ? result : nil)
    }
}
