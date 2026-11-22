import Charts
import HealthAnalysisCore
import SwiftUI

struct ExploreResultView<Status: View>: View {
    let application: HealthAnalysisApplication
    let result: AnalysisResult
    @ViewBuilder let status: () -> Status

    private var configuration: AnalysisConfiguration { result.configuration }
    private var isSleepDuration: Bool { result.configuration.output.isSleepDuration }

    var body: some View {
        findings(result)
        status()
        evidence(result)
        modeledInputs(result)
        coverage(result)
    }

    @ViewBuilder
    private func findings(_ result: AnalysisResult) -> some View {
        if let pair = configuration.interaction,
           let focal = result.modeledInputs.first(where: { $0.series == pair.focal }),
           let moderator = result.modeledInputs.first(where: { $0.series == pair.moderator }) {
            InteractionResultSection(
                focal: focal, moderator: moderator, estimate: result.interaction, isSleepDuration: isSleepDuration
            )
        }
        if result.estimates.isEmpty && configuration.interaction == nil {
            Section {
                Text("There isn’t enough evidence to estimate this association.")
                    .font(.headline)
            }
        }
        ForEach(Array(result.estimates.enumerated()), id: \.element.input) { index, estimate in
            if let input = result.modeledInputs.first(where: { $0.series == estimate.input }) {
                Section {
                    Text(estimate.finding.description(isSleepDuration: isSleepDuration, output: result.outputVariable))
                        .font(.headline)
                    EstimateDifference(estimate: estimate, input: input, isSleepDuration: isSleepDuration)
                        .monospacedDigit()
                        .accessibilityIdentifier(estimate.scale == .proportionalCountChange ? "explore.countEffect" : "explore.effect")
                    if let reference = estimate.reference,
                       let other = result.modeledInputs.first(where: { $0.series == reference.input }) {
                        Text("With \(other.name) at \(reference.value, format: .number) \(other.unit).")
                            .foregroundStyle(.secondary)
                    }
                    let intervalTitle: LocalizedStringKey = estimate.scale == .proportionalCountChange
                        ? "Approximate 95% uncertainty interval" : "Dependence-adjusted interval"
                    LabeledContent(intervalTitle) {
                        Text(intervalLabel(estimate, isSleepDuration: isSleepDuration))
                    }
                    .accessibilityIdentifier(index == 0 ? "explore.uncertainty" : "explore.uncertainty.\(index)")
                    EstimateChart(estimate: estimate, input: input, isSleepDuration: isSleepDuration)
                        .accessibilityIdentifier(index == 0 ? "explore.estimateChart" : "explore.estimateChart.\(index)")
                    if estimate.finding == .nearZero {
                        Text(isSleepDuration
                            ? "The full interval is within 15 minutes of zero for the reported increment."
                            : "The full interval is within 1 bpm of zero for the reported increment.")
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
                Text(reason.description(isSleepDuration: isSleepDuration))
                ForEach(result.modeledInputs.filter { reason.affectedInputs.contains($0.series) }) { input in
                    input.choiceLabel
                }
                if case .poorlyRepresentedInteraction(let support) = reason {
                    InteractionSupportRows(support: support)
                }
            }
            if let comparison = result.interaction {
                InteractionSupportRows(support: comparison.support)
            }
            if let days = result.evidence.dependenceLagDays {
                Text("The interval allows for dependence across up to \(days) calendar days.")
            }
            if result.modeledInputs.count > 1 {
                Text("Each estimate accounts for the other modeled inputs and has its own uncertainty interval.")
                    .foregroundStyle(.secondary)
            }
            Text("Other variables may also be associated with this output.")
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
                        input.choiceLabel
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
            Text("Each input shows how many paired days used its configured default.")
        }
    }

    private func coverage(_ result: AnalysisResult) -> some View {
        Section("Coverage") {
            ExploreTemporalSummary(configuration: result.configuration)
            LabeledContent("Paired days") {
                Text(result.coverage.usableDates.count, format: .number)
            }
            if result.configuration.behaviorWindow != .precedingDay {
                LabeledContent("Distinct behavior days") {
                    Text(result.coverage.distinctBehaviorDayCount, format: .number)
                }
                LabeledContent("Nonoverlapping windows") {
                    Text(result.coverage.nonOverlappingWindowCount, format: .number)
                }
            }
            if let first = result.coverage.firstDate, let last = result.coverage.lastDate {
                LabeledContent("Usable history") {
                    AnalysisDateRange(first: first, last: last, timeZone: result.configuration.timeZone)
                }
                LabeledContent("Days without a usable pair in this range") {
                    Text(result.coverage.missingDays, format: .number)
                }
            }
            LabeledContent("Paired days using a default") {
                Text(result.evidence.defaultDayCount, format: .number)
            }
            if let output = result.outputVariable {
                LabeledContent("Output") { Text(output.name) }
                LabeledContent("Paired output days using a default") {
                    Text(result.observations.count { $0.outputOrigin != .observation }, format: .number)
                }
                LabeledContent("Recorded zeros for the paired output") {
                    Text(result.observations.count { $0.outputOrigin == .observation && $0.outputTrackingValue == .count(0) }, format: .number)
                }
            }
            if let source = result.outputSource {
                LabeledContent("Output source") {
                    Text(source.name)
                }
            }
            NavigationLink("Usable dates and gaps") {
                ExploreCoverageView(result: result)
            }
            if result.outputVariable == nil { measurementsLink }
        }
    }

    private var measurementsLink: some View {
        NavigationLink("Inspect Health measurements") {
            HealthMeasurementHistoryView(
                history: application.healthMeasurements, presentation: isSleepDuration ? .sleep : .restingHeartRate
            )
        }
    }
}

private struct EstimateDifference: View {
    let estimate: AnalysisEstimate
    let input: AnalysisModeledInput
    let isSleepDuration: Bool

    var body: some View {
        estimateLabel(estimate, input: input, isSleepDuration: isSleepDuration)
    }
}

private struct EstimateChart: View {
    let estimate: AnalysisEstimate
    let input: AnalysisModeledInput
    let isSleepDuration: Bool

    private var scale: Double { isSleepDuration ? 60 : 1 }
    private var lower: Double { estimate.interval.lowerBound * scale }
    private var upper: Double { estimate.interval.upperBound * scale }
    private var axisLabel: LocalizedStringKey {
        if estimate.scale == .proportionalCountChange { return "Change in expected daily count" }
        return isSleepDuration ? "Difference in sleep duration (minutes)" : "Difference in resting heart rate (bpm)"
    }

    private var domain: ClosedRange<Double> {
        let first = min(0, lower)
        let last = max(0, upper)
        let padding = (last - first) * 0.1
        return (first - padding)...(last + padding)
    }

    var body: some View {
        Chart {
            RuleMark(x: .value("Zero difference", 0.0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
            RuleMark(
                xStart: .value("Lower limit", lower),
                xEnd: .value("Upper limit", upper),
                y: .value("Estimate", input.name)
            )
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            .foregroundStyle(Color.accentColor)
            PointMark(
                x: .value("Estimated difference", estimate.difference * scale),
                y: .value("Estimate", input.name)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartXScale(domain: domain)
        .chartXAxis {
            if estimate.scale == .proportionalCountChange {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    if let fraction = value.as(Double.self) {
                        AxisValueLabel { Text(fraction, format: countPercent) }
                    }
                }
            } else {
                AxisMarks()
            }
        }
        .chartXAxisLabel(axisLabel, position: .bottom, alignment: .center)
        .chartYAxis(.hidden)
        .frame(height: 95)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated difference and uncertainty for \(input.name)")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: Text {
        let interval = intervalLabel(estimate, isSleepDuration: isSleepDuration)
        if estimate.scale == .proportionalCountChange || input.kind == .tracked(.count) {
            let effect = estimateLabel(estimate, input: input, isSleepDuration: isSleepDuration)
            return Text("\(effect). Dependence-adjusted interval \(interval).")
        }
        if isSleepDuration {
            return Text("\(estimate.difference * scale, format: estimateNumber) minutes per \(estimate.inputIncrement, format: .number) \(input.unit) increase. Dependence-adjusted interval \(interval).")
        }
        return Text("\(estimate.difference, format: estimateNumber) beats per minute per \(estimate.inputIncrement, format: .number) \(input.unit) increase. Dependence-adjusted interval \(interval).")
    }
}

private struct ExploreCoverageView: View {
    let result: AnalysisResult

    private var timeZone: TimeZone { result.configuration.timeZone }
    private var hasStoredCounts: Bool {
        result.outputVariable?.kind == .tracked(.count) || result.modeledInputs.contains { $0.kind == .tracked(.count) }
    }

    var body: some View {
        List {
            Section("Question") {
                LabeledContent("Output") {
                    if let output = result.outputVariable {
                        Text(output.name)
                    } else {
                        Text(result.configuration.output.isSleepDuration ? "Sleep duration" : "Resting heart rate")
                    }
                }
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
                if result.outputVariable != nil {
                    Text("Each pair uses counts from a completed output day and inputs from before that day began.")
                } else if result.configuration.output.isSleepDuration {
                    Text("Each recorded wake date uses its longest completed sleep episode. Each input uses complete days before the episode began.")
                } else {
                    Text("Each input uses complete local days before the resting heart rate sample began.")
                }
                if result.configuration.behaviorWindow != .precedingDay {
                    Text("Each quantity is totaled across the selected window.")
                }
                if result.configuration.history != .fullHistory {
                    Text("History limits output dates. Earlier inputs can still complete a window.")
                }
            }

            Section("Gaps") {
                LabeledContent("Output days in selected history") {
                    Text(result.coverage.outputDayCount, format: .number)
                }
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

            if !result.coverage.outputDatesWithoutCompleteInput.isEmpty {
                Section("Outputs with incomplete windows") {
                    ForEach(result.coverage.outputDatesWithoutCompleteInput, id: \.self) { date in
                        AnalysisDateRange(first: date, last: date, timeZone: timeZone)
                    }
                }
            }

            Section("Usable dates") {
                if result.coverage.usableDates.isEmpty {
                    Text("No paired days.")
                }
                ForEach(result.observations) { observation in
                    let date = observation.outputDate
                    if hasStoredCounts {
                        NavigationLink {
                            CountObservationView(result: result, observation: observation)
                        } label: {
                            AnalysisDateRange(first: date, last: date, timeZone: timeZone)
                        }
                        .accessibilityIdentifier("explore.pairedCounts")
                    } else {
                        AnalysisDateRange(first: date, last: date, timeZone: timeZone)
                    }
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

private let countPercent = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(0...2))

func estimateLabel(_ estimate: AnalysisEstimate, input: AnalysisModeledInput, isSleepDuration: Bool) -> Text {
    let countInput = input.kind == .tracked(.count)
    if estimate.scale == .proportionalCountChange {
        if countInput {
            return Text("\(estimate.difference, format: countPercent) change in expected daily count per additional event")
        }
        return Text("\(estimate.difference, format: countPercent) change in expected daily count per \(estimate.inputIncrement, format: .number) \(input.unit) increase")
    }
    if isSleepDuration {
        if countInput {
            return Text("\(estimate.difference * 60, format: estimateNumber) minutes per additional event")
        }
        return Text("\(estimate.difference * 60, format: estimateNumber) minutes per \(estimate.inputIncrement, format: .number) \(input.unit) increase")
    }
    if countInput {
        return Text("\(estimate.difference, format: estimateNumber) bpm per additional event")
    }
    return Text("\(estimate.difference, format: estimateNumber) bpm per \(estimate.inputIncrement, format: .number) \(input.unit) increase")
}

private extension AnalysisModeledInput {
    var choiceLabel: Text {
        if kind == .tracked(.count) {
            Text("\(name) (count)")
        } else {
            Text("\(name) (\(unit))")
        }
    }
}

private func intervalLabel(_ estimate: AnalysisEstimate, isSleepDuration: Bool) -> String {
    if estimate.scale == .proportionalCountChange {
        return String(localized: "\(estimate.interval.lowerBound, format: countPercent) to \(estimate.interval.upperBound, format: countPercent)")
    }
    if isSleepDuration {
        return String(localized: "\(estimate.interval.lowerBound * 60, format: estimateNumber) to \(estimate.interval.upperBound * 60, format: estimateNumber) minutes")
    }
    return String(localized: "\(estimate.interval.lowerBound, format: estimateNumber) to \(estimate.interval.upperBound, format: estimateNumber) bpm")
}

private extension AnalysisEstimate.Finding {
    func description(isSleepDuration: Bool, output: AnalysisVariable?) -> LocalizedStringKey {
        if let output {
            switch self {
            case .higher: return "Higher values were associated with a higher daily count for \(output.name)."
            case .lower: return "Higher values were associated with a lower daily count for \(output.name)."
            case .nearZero, .uncertain: break
            }
        }
        return switch (self, isSleepDuration) {
        case (.higher, false): "Higher values were associated with higher resting heart rate."
        case (.lower, false): "Higher values were associated with lower resting heart rate."
        case (.higher, true): "Higher values were associated with longer sleep."
        case (.lower, true): "Higher values were associated with shorter sleep."
        case (.nearZero, _): "The estimated association was close to zero."
        case (.uncertain, _): "The association is uncertain."
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
        case .countLogLinearV1: "Poisson regression for daily counts"
        case .numericInteractionV1: "Numeric linear regression with an interaction"
        }
    }
}

private extension AnalysisEvidence.Reason {
    func description(isSleepDuration: Bool) -> LocalizedStringKey {
        switch self {
        case .inadequateCoverage: "This comparison needs at least 42 paired days."
        case .inadequateJointCoverage(let days): "This model needs at least \(days) paired days."
        case .limitedNonOverlappingWindows: "This comparison needs at least six windows that share no behavior days."
        case .overlappingBehaviorWindows: "Some windows share behavior days, which limits confidence in this result."
        case .noObservedInputs: "Every day in the paired input windows comes from a default."
        case .limitedInputVariation: "The input varied too little across paired days."
        case .uncertaintyUnavailable: "The paired values could not support a usable uncertainty interval."
        case .limitedHistory: "The analysis uses fewer than 90 paired days."
        case .sparseCoverage: "Fewer than three quarters of days in the usable history had a pair."
        case .manyDefaults: "More than one quarter of paired days used at least one assumed value."
        case .wideInterval:
            isSleepDuration
                ? "The uncertainty interval spans more than 30 minutes for the reported increment."
                : "The uncertainty interval spans more than 2 bpm for the reported increment."
        case .indeterminateInterval: "An interval includes no change and also allows an increase or decrease."
        case .adequateCoverageAndPrecision: "The analysis has at least 90 paired days, good overlap, limited default use, and a narrow interval."
        case .defaultOnlyOutput: "Every paired output count comes from a default."
        case .lowVariationOutput: "Recorded output counts do not vary on paired days."
        case .sparseObservedCountOutput: "Too few recorded output counts show repeated variation and nonzero counts."
        case .countModelUnavailable: "The count model could not estimate a stable association. Some input values may only occur with zero output counts."
        case .countModelLimitations: "The model assumes a constant proportional change per input increment. Longer dependence, unmeasured variables, and default values can affect the estimate."
        case .adjustedModelLimitations: "Evidence is limited to this history and the variables included in the model."
        case .collinearInputs: "These inputs vary together too closely to estimate their separate associations."
        case .defaultOnlyInputs: "These inputs only have defaults on paired days."
        case .lowVariationInputs: "These inputs vary too little on paired days."
        case .poorlyRepresentedInteraction: "Too few fully recorded windows support the lower and higher combinations."
        }
    }

    var affectedInputs: Set<AnalysisSeriesID> {
        switch self {
        case .collinearInputs(let inputs), .defaultOnlyInputs(let inputs), .lowVariationInputs(let inputs): inputs
        default: []
        }
    }
}
