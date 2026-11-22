import Charts
import HealthAnalysisCore
import SwiftUI

struct ExploreResultView<Status: View>: View {
    let application: HealthAnalysisApplication
    let result: AnalysisResult
    @ViewBuilder let status: () -> Status

    private var isAdjusted: Bool { result.modeledInputs.count > 1 }

    var body: some View {
        findings
        if result.lastHealthReadFailure != nil {
            Section {
                Text("The latest Health check failed. This analysis uses earlier imported measurements.")
                    .foregroundStyle(.secondary)
            }
        }
        status()
        Section("Inspect result") {
            NavigationLink("Observed measurements") {
                AnalysisObservedView(result: result, log: application.manualLog)
                    .id(result.configuration)
            }
            NavigationLink("Usable dates and gaps") {
                AnalysisCoverageView(result: result, application: application)
            }
            NavigationLink("Model and evidence") {
                AnalysisModelView(result: result, log: application.manualLog)
            }
        }
    }

    @ViewBuilder
    private var findings: some View {
        if result.estimates.isEmpty {
            Section {
                Text("There isn’t enough evidence to estimate this association.")
                    .font(.headline)
                confidence
                ForEach(result.evidence.reasons, id: \.self) { reason in
                    AnalysisReasonRows(reason: reason, inputs: result.modeledInputs)
                }
                insufficientDataLink
            }
        }
        ForEach(Array(result.estimates.enumerated()), id: \.element.input) { index, estimate in
            if let input = result.modeledInputs.first(where: { $0.series == estimate.input }) {
                Section {
                    let estimateTitle: LocalizedStringKey = isAdjusted ? "Adjusted estimate" : "Association estimate"
                    Text(estimateTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(estimate.finding.description)
                        .font(.headline)
                    Text("\(estimate.difference, format: estimateNumber) bpm per \(estimate.inputIncrement, format: .number) \(input.unit) increase")
                        .monospacedDigit()
                    LabeledContent("Approximate 95% uncertainty interval") {
                        Text(intervalLabel(estimate))
                    }
                    .accessibilityIdentifier(index == 0 ? "explore.uncertainty" : "explore.uncertainty.\(index)")
                    EstimateChart(estimate: estimate, input: input, isAdjusted: isAdjusted)
                        .accessibilityIdentifier(index == 0 ? "explore.estimateChart" : "explore.estimateChart.\(index)")
                    if estimate.finding == .nearZero {
                        Text("The full interval is within 1 bpm of zero for the reported increment.")
                            .foregroundStyle(.secondary)
                    }
                    if index == 0 {
                        confidence
                        ForEach(result.evidence.reasons.filter { $0 != .adequateCoverageAndPrecision }, id: \.self) { reason in
                            AnalysisReasonRows(reason: reason, inputs: result.modeledInputs)
                        }
                    }
                } header: {
                    switch input.role {
                    case .input: Text(input.name)
                    case .adjustment: Text("Account for · \(input.name)")
                    }
                }
            }
        }
    }

    private var confidence: some View {
        LabeledContent("Confidence") {
            Text(result.evidence.grade.description)
        }
    }

    @ViewBuilder
    private var insufficientDataLink: some View {
        let affected = Set(result.evidence.reasons.flatMap(\.affectedInputs))
        if let input = result.modeledInputs.first(where: { affected.contains($0.series) })
            ?? (result.evidence.reasons.contains(.noObservedInputs) || result.evidence.reasons.contains(.limitedInputVariation)
                ? result.modeledInputs.first : nil) {
            NavigationLink("Inspect input records") {
                AnalysisObservedView(result: result, log: application.manualLog, initialInput: input.series)
                    .id(result.configuration)
            }
        } else {
            NavigationLink("Inspect available data") {
                AnalysisCoverageView(result: result, application: application)
            }
        }
    }
}

private struct AnalysisModelView: View {
    let result: AnalysisResult
    let log: ManualLog

    var body: some View {
        let hasEstimates = !result.estimates.isEmpty
        List {
            Section("Model and uncertainty") {
                LabeledContent("Model") { Text(result.model.description) }
                if hasEstimates {
                    Text("The model includes an intercept.")
                }
                if let days = result.evidence.dependenceLagDays {
                    Text("The interval accounts for dependence across up to \(days) calendar days.")
                }
                if hasEstimates && result.modeledInputs.count > 1 {
                    Text("Each estimate accounts for the other modeled inputs and has its own uncertainty interval.")
                }
                Text("Other variables may also be associated with resting heart rate.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(result.modeledInputs) { input in
                    let role: LocalizedStringKey = input.role == .input ? "Input" : "Adjustment input"
                    NavigationLink {
                        AnalysisInputEvidenceView(result: result, input: input, log: log)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("\(input.name) (\(input.unit))")
                            Text(role)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(Text("\(input.name) (\(input.unit)), \(Text(role))"))
                }
            } header: {
                Text(hasEstimates ? "Modeled inputs" : "Inputs assessed")
            }
            Section("Evidence") {
                LabeledContent("Confidence") { Text(result.evidence.grade.description) }
                ForEach(result.evidence.reasons, id: \.self) { reason in
                    AnalysisReasonRows(reason: reason, inputs: result.modeledInputs)
                }
            }
        }
        .navigationTitle("Model and evidence")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AnalysisReasonRows: View {
    let reason: AnalysisEvidence.Reason
    let inputs: [AnalysisModeledInput]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reason.description)
            ForEach(inputs.filter { reason.affectedInputs.contains($0.series) }) { input in
                Text("\(input.name) (\(input.unit))")
            }
        }
        .foregroundStyle(.secondary)
    }
}

private struct EstimateChart: View {
    let estimate: AnalysisEstimate
    let input: AnalysisModeledInput
    let isAdjusted: Bool
    @ScaledMetric private var chartHeight = 95.0

    private var domain: ClosedRange<Double> {
        let lower = min(0, estimate.interval.lowerBound)
        let upper = max(0, estimate.interval.upperBound)
        let padding = (upper - lower) * 0.1
        return (lower - padding)...(upper + padding)
    }

    var body: some View {
        Chart {
            RuleMark(x: .value("Zero difference", 0.0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
            RuleMark(
                xStart: .value("Lower limit", estimate.interval.lowerBound),
                xEnd: .value("Upper limit", estimate.interval.upperBound),
                y: .value("Estimate", input.name)
            )
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            .foregroundStyle(Color.accentColor)
            PointMark(
                x: .value("Estimated difference", estimate.difference),
                y: .value("Estimate", input.name)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartXScale(domain: domain)
        .chartXAxisLabel("Difference in resting heart rate (bpm)", position: .bottom, alignment: .center)
        .chartYAxis(.hidden)
        .frame(height: chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isAdjusted
            ? Text("Adjusted estimate and uncertainty for \(input.name)")
            : Text("Association estimate and uncertainty for \(input.name)")
        )
        .accessibilityValue(
            Text("\(Text(estimate.finding.description)) \(estimate.difference, format: estimateNumber) bpm per \(estimate.inputIncrement, format: .number) \(input.unit) increase, with an approximate 95% interval of \(intervalLabel(estimate)).")
        )
    }
}

private let estimateNumber = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))

private func intervalLabel(_ estimate: AnalysisEstimate) -> String {
    String(localized: "\(estimate.interval.lowerBound, format: estimateNumber) to \(estimate.interval.upperBound, format: estimateNumber) bpm")
}

private extension AnalysisEstimate.Finding {
    var description: LocalizedStringKey {
        switch self {
        case .higher: "Higher values were associated with higher resting heart rate."
        case .lower: "Higher values were associated with lower resting heart rate."
        case .nearZero: "The estimated association was close to zero."
        case .uncertain: "The association is uncertain."
        }
    }
}

private extension AnalysisEvidence.Grade {
    var description: LocalizedStringKey {
        switch self {
        case .insufficient: "Insufficient"
        case .low: "Low"
        case .moderate: "Moderate"
        }
    }
}

private extension AnalysisModel {
    var description: LocalizedStringKey {
        switch self {
        case .caffeineLinearV1: "Single-input linear association"
        case .numericLinearV1: "Numeric linear regression"
        }
    }
}

private extension AnalysisEvidence.Reason {
    var description: LocalizedStringKey {
        switch self {
        case .inadequateCoverage: "This comparison needs at least 42 paired days."
        case .inadequateJointCoverage(let days): "This model needs at least \(days) paired days."
        case .noObservedInputs: "Every paired value for this input comes from a default."
        case .limitedInputVariation: "The input varied too little across paired days."
        case .uncertaintyUnavailable: "The paired values could not support a usable uncertainty interval."
        case .limitedHistory: "The analysis uses fewer than 90 paired days."
        case .sparseCoverage: "Fewer than three quarters of days in the usable history had a pair."
        case .manyDefaults: "More than one quarter of paired days used at least one assumed input."
        case .wideInterval: "The uncertainty interval spans more than 2 bpm for the reported increment."
        case .indeterminateInterval: "An interval includes zero and allows differences away from zero."
        case .adequateCoverageAndPrecision: "The analysis has at least 90 paired days, good overlap, limited default use, and a narrow interval."
        case .adjustedModelLimitations: "Evidence is limited to this history and the variables included in the model."
        case .collinearInputs: "These inputs vary together too closely to estimate their separate associations."
        case .defaultOnlyInputs: "These inputs only have defaults on paired days."
        case .lowVariationInputs: "These inputs vary too little on paired days."
        }
    }

    var affectedInputs: Set<AnalysisSeriesID> {
        switch self {
        case .collinearInputs(let inputs), .defaultOnlyInputs(let inputs), .lowVariationInputs(let inputs): inputs
        default: []
        }
    }
}
