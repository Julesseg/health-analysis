import Charts
import HealthAnalysisCore
import SwiftUI

struct ExploreResultView: View {
    let application: HealthAnalysisApplication
    let configuration: AnalysisConfiguration

    @State private var run: Result<AnalysisResult, AnalysisRunFailure>?

    var body: some View {
        List {
            switch run {
            case .success(let result):
                findings(result)
                evidence(result)
                modeledInputs(result)
                coverage(result)
            case .failure(let failure):
                Section {
                    Text(failure.description)
                    Button("Retry", action: analyze)
                    measurementsLink
                }
            case nil:
                ProgressView("Analyzing…")
            }
        }
        .navigationTitle("Analysis result")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if run == nil { analyze() }
        }
    }

    @ViewBuilder
    private func findings(_ result: AnalysisResult) -> some View {
        if result.estimates.isEmpty {
            Section {
                Text("There isn’t enough evidence to estimate this association.")
                    .font(.headline)
            }
        }
        ForEach(Array(result.estimates.enumerated()), id: \.element.input) { index, estimate in
            if let input = result.modeledInputs.first(where: { $0.series == estimate.input }) {
                Section {
                    Text(estimate.finding.description)
                        .font(.headline)
                    Text("\(estimate.difference, format: estimateNumber) bpm per \(estimate.inputIncrement, format: .number) \(input.unit) increase")
                        .monospacedDigit()
                    LabeledContent("Approximate 95% uncertainty interval") {
                        Text(intervalLabel(estimate))
                    }
                    .accessibilityIdentifier(index == 0 ? "explore.uncertainty" : "explore.uncertainty.\(index)")
                    EstimateChart(estimate: estimate, input: input)
                        .accessibilityIdentifier(index == 0 ? "explore.estimateChart" : "explore.estimateChart.\(index)")
                    if estimate.finding == .nearZero {
                        Text("The full interval is within 1 bpm of zero for the reported increment.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    switch input.role {
                    case .input: Text(input.name)
                    case .adjustment: Text("Account for · \(input.name)")
                    }
                }
            }
        }
        if result.lastHealthReadFailure != nil {
            Section {
                Text("The latest Health check failed. This analysis uses earlier imported measurements.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func evidence(_ result: AnalysisResult) -> some View {
        Section("Evidence") {
            LabeledContent("Confidence") {
                Text(result.evidence.grade.description)
            }
            LabeledContent("Model") {
                Text(result.model.description)
            }
            ForEach(result.evidence.reasons, id: \.self) { reason in
                Text(reason.description)
                ForEach(result.modeledInputs.filter { reason.affectedInputs.contains($0.series) }) { input in
                    Text("\(input.name) (\(input.unit))")
                }
            }
            if let days = result.evidence.dependenceLagDays {
                Text("The interval accounts for dependence across up to \(days) calendar days.")
            }
            if result.modeledInputs.count > 1 {
                Text("Each estimate accounts for the other modeled inputs and has its own uncertainty interval.")
                    .foregroundStyle(.secondary)
            }
            Text("Other variables may also be associated with resting heart rate.")
                .foregroundStyle(.secondary)
        }
    }

    private func modeledInputs(_ result: AnalysisResult) -> some View {
        Section {
            ForEach(result.modeledInputs) { input in
                LabeledContent {
                    Text(input.defaultDayCount, format: .number)
                } label: {
                    VStack(alignment: .leading) {
                        Text("\(input.name) (\(input.unit))")
                        Text(input.role == .input ? "Input" : "Adjustment input")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityValue(Text("\(input.defaultDayCount) paired days using a default"))
            }
        } header: {
            Text("Modeled inputs")
        } footer: {
            Text("Quantities come from the daily log. Counts show paired days using a default for each input.")
        }
    }

    private func coverage(_ result: AnalysisResult) -> some View {
        Section("Coverage") {
            LabeledContent("Paired days") {
                Text(result.coverage.usableDates.count, format: .number)
            }
            if let first = result.coverage.firstDate, let last = result.coverage.lastDate {
                LabeledContent("Usable history") {
                    AnalysisDateRange(first: first, last: last, timeZone: configuration.timeZone)
                }
                LabeledContent("Days without a usable pair in this range") {
                    Text(result.coverage.missingDays, format: .number)
                }
            }
            LabeledContent("Paired days using a default") {
                Text(result.evidence.defaultDayCount, format: .number)
            }
            if let source = result.outputSource {
                LabeledContent("Resting heart rate source") {
                    Text(source.name)
                }
            }
            NavigationLink("Usable dates and gaps") {
                ExploreCoverageView(result: result)
            }
            measurementsLink
        }
    }

    private var measurementsLink: some View {
        NavigationLink("Inspect Health measurements") {
            HealthMeasurementHistoryView(
                history: application.healthMeasurements, presentation: .restingHeartRate
            )
        }
    }

    private func analyze() {
        do {
            run = .success(try application.analyze(configuration))
        } catch {
            run = .failure(error)
        }
    }
}

private struct EstimateChart: View {
    let estimate: AnalysisEstimate
    let input: AnalysisModeledInput

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
        .frame(height: 95)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated difference and uncertainty for \(input.name)")
        .accessibilityValue(
            Text("\(estimate.difference, format: estimateNumber) bpm per \(estimate.inputIncrement, format: .number) \(input.unit) increase, with an approximate 95% interval of \(intervalLabel(estimate)).")
        )
    }
}

private struct ExploreCoverageView: View {
    let result: AnalysisResult

    private var timeZone: TimeZone { result.configuration.timeZone }

    var body: some View {
        List {
            Section("Question") {
                LabeledContent("Output") { Text("Resting heart rate") }
                LabeledContent("Behavior window") { Text("Complete preceding day") }
                LabeledContent("History") { Text("Full usable history") }
                LabeledContent("Analysis time zone") {
                    Text(timeZone.identifier)
                }
                if let lastRead = result.healthHistoryReadAt {
                    LabeledContent("Last successful Health check") {
                        Text(lastRead, format: .dateTime.year().month().day().hour().minute())
                    }
                }
                if let source = result.outputSource {
                    LabeledContent("Source identifier") {
                        Text(source.bundleIdentifier)
                    }
                }
                Text("Each pair uses a complete input window before the resting heart rate sample began.")
            }

            Section("Gaps") {
                LabeledContent("Output days without a complete input") {
                    Text(result.coverage.outputDaysWithoutCompleteInput, format: .number)
                }
                if !result.coverage.usableDates.isEmpty && result.coverage.gaps.isEmpty {
                    Text("No gaps between usable dates.")
                }
                ForEach(result.coverage.gaps) { gap in
                    AnalysisDateRange(first: gap.firstDate, last: gap.lastDate, timeZone: timeZone)
                }
            }

            Section("Usable dates") {
                if result.coverage.usableDates.isEmpty {
                    Text("No paired days.")
                }
                ForEach(result.coverage.usableDates, id: \.self) { date in
                    AnalysisDateRange(first: date, last: date, timeZone: timeZone)
                }
            }
        }
        .navigationTitle("Usable dates and gaps")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AnalysisDateRange: View {
    let first: Date
    let last: Date
    let timeZone: TimeZone

    var body: some View {
        if first == last {
            Text(first, format: format)
        } else {
            Text("\(first, format: format) – \(last, format: format)")
        }
    }

    private var format: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        format.timeZone = timeZone
        return format
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

private extension AnalysisRunFailure {
    var description: LocalizedStringKey {
        switch self {
        case .unsupportedConfiguration: "This analysis configuration is unavailable."
        case .inputUnavailable: "A selected quantity is unavailable."
        case .manualLogUnavailable: "Couldn’t open the daily log."
        case .chooseOutputSource: "Choose a preferred resting heart rate source in Health measurements."
        case .healthHistoryUnavailable: "Couldn’t use Health history. Check Health measurements and try again."
        case .healthHistoryLoading: "Health measurements are still being checked. Try again when the check finishes."
        }
    }
}
