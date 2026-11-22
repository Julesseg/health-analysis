import Charts
import HealthAnalysisCore
import SwiftUI

struct ExploreResultView<Status: View>: View {
    let application: HealthAnalysisApplication
    let result: AnalysisResult
    @ViewBuilder let status: () -> Status

    private var isSleepDuration: Bool { result.configuration.output.isSleepDuration }
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
            ExploreTemporalSummary(configuration: result.configuration)
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
        if let pair = result.interactionInputs {
            InteractionResultSection(
                focal: pair.focal, moderator: pair.moderator, estimate: result.interaction, isSleepDuration: isSleepDuration
            )
        }
        if result.estimates.isEmpty {
            Section {
                if result.interactionInputs == nil {
                    Text("There isn’t enough evidence to estimate this association.")
                        .font(.headline)
                }
                confidence
                if let event = result.categoryEvent {
                    LabeledContent("Output event", value: event.name)
                }
                LabeledContent("Paired days", value: result.coverage.usableDates.count.formatted())
                if result.evidence.reasons.contains(.limitedNonOverlappingWindows) {
                    LabeledContent("Nonoverlapping windows", value: result.coverage.nonOverlappingWindowCount.formatted())
                }
                ForEach(result.evidence.reasons, id: \.self) { reason in
                    AnalysisReasonRows(reason: reason, result: result)
                }
                insufficientDataLink
            }
        }
        ForEach(Array(result.estimates.enumerated()), id: \.element.input) { index, estimate in
            if let input = result.modeledInputs.first(where: { $0.series == estimate.input }) {
                let reference = referenceCondition(for: estimate)
                let contrast = result.categoryContrast(for: input.series)
                let event = result.categoryEvent
                let categoryEffect = categoryEffectLabel(
                    estimate, input: input, contrast: contrast, event: event, output: result.outputVariable,
                    isSleepDuration: isSleepDuration
                )
                let direction = estimateDirection(
                    estimate, input: input, contrast: contrast, event: event, output: result.outputVariable, isSleepDuration: isSleepDuration
                )
                Section {
                    let estimateTitle: LocalizedStringKey = isAdjusted ? "Adjusted estimate" : "Association estimate"
                    Text(estimateTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    direction.font(.headline)
                    (categoryEffect ?? estimateLabel(estimate, input: input, isSleepDuration: isSleepDuration, output: result.outputVariable))
                        .monospacedDigit()
                        .accessibilityIdentifier(effectIdentifier(estimate, input: input, categoryEffect: categoryEffect))
                    if let reference {
                        reference.foregroundStyle(.secondary)
                    }
                    let intervalTitle: LocalizedStringKey = estimate.scale == .difference
                        ? "Dependence-adjusted interval" : "Approximate 95% uncertainty interval"
                    LabeledContent(intervalTitle) {
                        Text(intervalLabel(estimate, isSleepDuration: isSleepDuration))
                    }
                    .accessibilityIdentifier(index == 0 ? "explore.uncertainty" : "explore.uncertainty.\(index)")
                    EstimateChart(
                        estimate: estimate, input: input, isSleepDuration: isSleepDuration, output: result.outputVariable,
                        isAdjusted: isAdjusted, reference: reference, direction: direction, categoryEffect: categoryEffect
                    )
                    .accessibilityIdentifier(index == 0 ? "explore.estimateChart" : "explore.estimateChart.\(index)")
                    if estimate.finding == .nearZero {
                        Text(isSleepDuration
                            ? "The full interval is within 15 minutes of zero for the reported increment."
                            : "The full interval is within 1 bpm of zero for the reported increment.")
                            .foregroundStyle(.secondary)
                    }
                    if index == 0 {
                        confidence
                        ForEach(result.evidence.reasons.filter { $0 != .adequateCoverageAndPrecision }, id: \.self) { reason in
                            AnalysisReasonRows(reason: reason, result: result)
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

    private func referenceCondition(for estimate: AnalysisEstimate) -> Text? {
        guard let reference = estimate.reference,
              let other = result.modeledInputs.first(where: { $0.series == reference.input }) else { return nil }
        return Text("With \(other.name) at \(reference.value, format: .number) \(other.unit).")
    }

    private func effectIdentifier(_ estimate: AnalysisEstimate, input: AnalysisModeledInput, categoryEffect: Text?) -> String {
        if categoryEffect != nil { return "explore.category.effect" }
        if estimate.scale == .ratingThresholdProbabilityDifference || input.kind?.ratingThreshold != nil {
            return "explore.ratingEffect"
        }
        if estimate.scale == .probabilityDifference { return "explore.binaryEffect" }
        return estimate.scale == .proportionalCountChange ? "explore.countEffect" : "explore.effect"
    }

    private var confidence: some View {
        LabeledContent("Confidence") {
            Text(result.evidence.grade.description)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Confidence")
        .accessibilityValue(Text(result.evidence.grade.description))
        .accessibilityIdentifier("explore.confidence")
    }

    @ViewBuilder
    private var insufficientDataLink: some View {
        if let input = affectedInput {
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

    private var affectedInput: AnalysisModeledInput? {
        let affected = Set(result.evidence.reasons.flatMap(\.affectedInputs))
        if let input = result.modeledInputs.first(where: { affected.contains($0.series) }) { return input }
        if result.evidence.reasons.contains(where: { reason in
            if case .poorlyRepresentedInteraction = reason { return true }
            return false
        }) {
            return result.interactionInputs?.focal
        }
        if result.evidence.reasons.contains(.noObservedInputs) || result.evidence.reasons.contains(.limitedInputVariation) {
            return result.modeledInputs.first
        }
        return nil
    }
}

struct AnalysisModelView: View {
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
                    Text("The interval allows for dependence across up to \(days) calendar days.")
                }
                if hasEstimates && result.model == .binaryLogisticV1 {
                    Text("Probability differences are averaged across paired days. Numeric inputs use days where the full increase fits within the recorded range.")
                }
                if hasEstimates && result.modeledInputs.count > 1 {
                    Text("Each estimate accounts for the other modeled inputs and has its own uncertainty interval.")
                }
                Text("Other variables may also be associated with this output.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(result.modeledInputs) { input in
                    let role: LocalizedStringKey = input.role == .input ? "Input" : "Adjustment input"
                    NavigationLink {
                        AnalysisInputEvidenceView(result: result, input: input, log: log)
                    } label: {
                        VStack(alignment: .leading) {
                            input.choiceLabel
                            Text(role)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(Text("\(input.choiceLabel), \(Text(role))"))
                }
                if let pair = result.interactionInputs {
                    LabeledContent("Interaction") {
                        Text("\(pair.focal.name) × \(pair.moderator.name)")
                    }
                }
            } header: {
                Text(hasEstimates ? "Modeled inputs" : "Inputs assessed")
            }
            RatingSupportSections(result: result)
            AnalysisCategoryEvidenceRows(result: result)
            Section("Evidence") {
                LabeledContent("Confidence") { Text(result.evidence.grade.description) }
                ForEach(result.evidence.reasons, id: \.self) { reason in
                    AnalysisReasonRows(reason: reason, result: result)
                    if case .poorlyRepresentedInteraction(let support) = reason {
                        InteractionSupportRows(support: support)
                    }
                }
                if let comparison = result.interaction {
                    InteractionSupportRows(support: comparison.support)
                }
            }
        }
        .navigationTitle("Model and evidence")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AnalysisReasonRows: View {
    let reason: AnalysisEvidence.Reason
    let result: AnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reason.description(isSleepDuration: result.configuration.output.isSleepDuration, isYesNoOutput: result.outputVariable?.kind == .tracked(.yesNo)))
            ForEach(result.modeledInputs.filter { reason.affectedInputs.contains($0.series) }) { input in
                input.choiceLabel
            }
        }
        .foregroundStyle(.secondary)
    }
}

private struct EstimateChart: View {
    let estimate: AnalysisEstimate
    let input: AnalysisModeledInput
    let isSleepDuration: Bool
    let output: AnalysisVariable?
    let isAdjusted: Bool
    let reference: Text?
    let direction: Text
    let categoryEffect: Text?
    @ScaledMetric private var chartHeight = 95.0

    private var scale: Double {
        if estimate.scale.isProbabilityDifference { return 100 }
        return isSleepDuration ? 60 : 1
    }
    private var lower: Double { estimate.interval.lowerBound * scale }
    private var upper: Double { estimate.interval.upperBound * scale }
    private var axisLabel: LocalizedStringKey {
        if estimate.scale == .probabilityDifference { return "Difference in Yes probability (percentage points)" }
        if estimate.scale == .proportionalCountChange { return "Change in expected daily count" }
        if estimate.scale == .ratingThresholdProbabilityDifference { return "Difference in probability (percentage points)" }
        if estimate.scale == .proportionalCategoryOddsChange { return "Change in odds of the selected category" }
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
            if estimate.scale == .proportionalCountChange || estimate.scale == .proportionalCategoryOddsChange {
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
        .frame(height: chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isAdjusted
            ? Text("Adjusted estimate and uncertainty for \(input.name)")
            : Text("Association estimate and uncertainty for \(input.name)")
        )
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: Text {
        if let reference { return Text("\(estimateAccessibilityValue) \(reference)") }
        return estimateAccessibilityValue
    }

    private var estimateAccessibilityValue: Text {
        let interval = intervalLabel(estimate, isSleepDuration: isSleepDuration)
        if let categoryEffect {
            return Text("\(direction) \(categoryEffect). Dependence-adjusted interval \(interval).")
        }
        if estimate.scale != .difference || input.kind == .tracked(.count) || input.kind == .tracked(.yesNo) || input.kind?.ratingThreshold != nil {
            let effect = estimateLabel(estimate, input: input, isSleepDuration: isSleepDuration, output: output)
            return Text("\(direction) \(effect). Dependence-adjusted interval \(interval).")
        }
        if isSleepDuration {
            return Text("\(direction) \(estimate.difference * scale, format: estimateNumber) minutes per \(estimate.inputIncrement, format: .number) \(input.unit) increase. Dependence-adjusted interval \(interval).")
        }
        return Text("\(direction) \(estimate.difference, format: estimateNumber) beats per minute per \(estimate.inputIncrement, format: .number) \(input.unit) increase. Dependence-adjusted interval \(interval).")
    }
}

private let estimateNumber = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))

private let countPercent = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(0...2))

func estimateLabel(
    _ estimate: AnalysisEstimate, input: AnalysisModeledInput, isSleepDuration: Bool, output: AnalysisVariable? = nil
) -> Text {
    let inputThreshold = input.kind?.ratingThreshold
    let outputThreshold = output?.kind.ratingThreshold
    let countInput = input.kind == .tracked(.count)
    let yesNoInput = input.kind == .tracked(.yesNo)
    if inputThreshold != nil || outputThreshold != nil {
        let effect: Text
        if let output, let outputThreshold {
            effect = Text("\(estimate.difference * 100, format: estimateNumber) percentage points for \(output.name) at \(outputThreshold, format: .number) or above")
        } else if estimate.scale == .probabilityDifference {
            effect = Text("\(estimate.difference * 100, format: estimateNumber) percentage points in the probability of Yes")
        } else if estimate.scale == .proportionalCountChange {
            effect = Text("\(estimate.difference, format: countPercent) change in expected daily count")
        } else if isSleepDuration {
            effect = Text("\(estimate.difference * 60, format: estimateNumber) minutes")
        } else {
            effect = Text("\(estimate.difference, format: estimateNumber) bpm")
        }
        if let inputThreshold {
            return Text("\(effect) for \(input.name) at \(inputThreshold, format: .number) or above vs. below \(inputThreshold, format: .number)")
        }
        if yesNoInput { return Text("\(effect) for Yes versus No") }
        if countInput { return Text("\(effect) per additional event") }
        return Text("\(effect) per \(estimate.inputIncrement, format: .number) \(input.unit) increase")
    }
    if estimate.scale == .probabilityDifference {
        let points = estimate.difference * 100
        if yesNoInput {
            return Text("\(points, format: estimateNumber) percentage points in the probability of Yes (Yes versus No)")
        }
        if countInput {
            return Text("\(points, format: estimateNumber) percentage points in the probability of Yes per additional event")
        }
        return Text("\(points, format: estimateNumber) percentage points in the probability of Yes per \(estimate.inputIncrement, format: .number) \(input.unit) increase")
    }
    if estimate.scale == .proportionalCountChange {
        if yesNoInput {
            return Text("\(estimate.difference, format: countPercent) change in expected daily count for Yes versus No")
        }
        if countInput {
            return Text("\(estimate.difference, format: countPercent) change in expected daily count per additional event")
        }
        return Text("\(estimate.difference, format: countPercent) change in expected daily count per \(estimate.inputIncrement, format: .number) \(input.unit) increase")
    }
    if isSleepDuration {
        if yesNoInput {
            return Text("\(estimate.difference * 60, format: estimateNumber) minutes for Yes versus No")
        }
        if countInput {
            return Text("\(estimate.difference * 60, format: estimateNumber) minutes per additional event")
        }
        return Text("\(estimate.difference * 60, format: estimateNumber) minutes per \(estimate.inputIncrement, format: .number) \(input.unit) increase")
    }
    if yesNoInput {
        return Text("\(estimate.difference, format: estimateNumber) bpm for Yes versus No")
    }
    if countInput {
        return Text("\(estimate.difference, format: estimateNumber) bpm per additional event")
    }
    return Text("\(estimate.difference, format: estimateNumber) bpm per \(estimate.inputIncrement, format: .number) \(input.unit) increase")
}

private func categoryEffectLabel(
    _ estimate: AnalysisEstimate, input: AnalysisModeledInput, contrast: (reference: String, comparison: String)?,
    event: TrackingCategory?, output: AnalysisVariable?, isSleepDuration: Bool
) -> Text? {
    if let event {
        if let contrast {
            return Text("\(estimate.difference, format: countPercent) change in odds of \(event.name) for \(contrast.comparison) compared with \(contrast.reference)")
        }
        if input.kind == .tracked(.count) {
            return Text("\(estimate.difference, format: countPercent) change in odds of \(event.name) per additional event")
        }
        if let threshold = input.kind?.ratingThreshold {
            return Text("\(estimate.difference, format: countPercent) change in odds of \(event.name) for \(input.name) at \(threshold, format: .number) or above vs. below \(threshold, format: .number)")
        }
        return Text("\(estimate.difference, format: countPercent) change in odds of \(event.name) per \(estimate.inputIncrement, format: .number) \(input.unit) increase")
    }
    guard let contrast else { return nil }
    if let output, let threshold = output.kind.ratingThreshold {
        return Text("\(estimate.difference * 100, format: estimateNumber) percentage points for \(output.name) at \(threshold, format: .number) or above for \(contrast.comparison) compared with \(contrast.reference)")
    }
    if estimate.scale == .proportionalCountChange {
        return Text("\(estimate.difference, format: countPercent) change in expected daily count for \(contrast.comparison) compared with \(contrast.reference)")
    }
    if isSleepDuration {
        return Text("\(estimate.difference * 60, format: estimateNumber) minutes for \(contrast.comparison) compared with \(contrast.reference)")
    }
    return Text("\(estimate.difference, format: estimateNumber) bpm for \(contrast.comparison) compared with \(contrast.reference)")
}

private func estimateDirection(
    _ estimate: AnalysisEstimate, input: AnalysisModeledInput, contrast: (reference: String, comparison: String)?,
    event: TrackingCategory?, output: AnalysisVariable?, isSleepDuration: Bool
) -> Text {
    if let event {
        switch estimate.finding {
        case .higher: return Text("The estimated odds of \(event.name) were higher.")
        case .lower: return Text("The estimated odds of \(event.name) were lower.")
        case .nearZero, .uncertain: return Text("The association with \(event.name) is uncertain.")
        }
    }
    if let contrast {
        if let output, let threshold = output.kind.ratingThreshold {
            switch estimate.finding {
            case .higher: return Text("\(contrast.comparison) was associated with a higher probability of \(output.name) at \(threshold, format: .number) or above.")
            case .lower: return Text("\(contrast.comparison) was associated with a lower probability of \(output.name) at \(threshold, format: .number) or above.")
            case .nearZero, .uncertain: break
            }
        }
        switch estimate.finding {
        case .higher:
            if output != nil { return Text("The estimated daily count was higher for \(contrast.comparison).") }
            if isSleepDuration { return Text("\(contrast.comparison) was associated with longer sleep.") }
            return Text("\(contrast.comparison) was associated with higher resting heart rate.")
        case .lower:
            if output != nil { return Text("The estimated daily count was lower for \(contrast.comparison).") }
            if isSleepDuration { return Text("\(contrast.comparison) was associated with shorter sleep.") }
            return Text("\(contrast.comparison) was associated with lower resting heart rate.")
        case .nearZero, .uncertain:
            break
        }
    }
    return Text(estimate.finding.description(isSleepDuration: isSleepDuration, output: output, input: input))
}

func intervalLabel(_ estimate: AnalysisEstimate, isSleepDuration: Bool) -> String {
    if estimate.scale.isProbabilityDifference {
        return String(localized: "\(estimate.interval.lowerBound * 100, format: estimateNumber) to \(estimate.interval.upperBound * 100, format: estimateNumber) percentage points")
    }
    if estimate.scale != .difference {
        return String(localized: "\(estimate.interval.lowerBound, format: countPercent) to \(estimate.interval.upperBound, format: countPercent)")
    }
    return numericAssociationIntervalLabel(estimate.interval, isSleepDuration: isSleepDuration)
}

func numericAssociationIntervalLabel(_ interval: ClosedRange<Double>, isSleepDuration: Bool) -> String {
    if isSleepDuration {
        return String(localized: "\(interval.lowerBound * 60, format: estimateNumber) to \(interval.upperBound * 60, format: estimateNumber) minutes")
    }
    return String(localized: "\(interval.lowerBound, format: estimateNumber) to \(interval.upperBound, format: estimateNumber) bpm")
}

private extension AnalysisEstimate.Finding {
    func description(isSleepDuration: Bool, output: AnalysisVariable?, input: AnalysisModeledInput) -> LocalizedStringKey {
        if let output, output.kind == .tracked(.yesNo) {
            switch self {
            case .higher: return "The model estimates a higher probability of Yes for \(output.name) in this comparison."
            case .lower: return "The model estimates a lower probability of Yes for \(output.name) in this comparison."
            case .nearZero, .uncertain: break
            }
        }
        if let output, let threshold = output.kind.ratingThreshold {
            switch self {
            case .higher: return "The higher input condition was associated with a higher probability of \(output.name) at \(threshold, format: .number) or above."
            case .lower: return "The higher input condition was associated with a lower probability of \(output.name) at \(threshold, format: .number) or above."
            case .nearZero, .uncertain: break
            }
        }
        if input.kind == .tracked(.yesNo) {
            switch self {
            case .higher, .lower:
                if output?.kind == .tracked(.count) {
                    return self == .higher ? "Yes was associated with a higher daily count than No."
                        : "Yes was associated with a lower daily count than No."
                }
                if isSleepDuration {
                    return self == .higher ? "Yes was associated with longer sleep than No."
                        : "Yes was associated with shorter sleep than No."
                }
                return self == .higher ? "Yes was associated with higher resting heart rate than No."
                    : "Yes was associated with lower resting heart rate than No."
            case .nearZero, .uncertain: break
            }
        }
        if let output, output.kind == .tracked(.count) {
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

extension AnalysisEvidence.Grade {
    var description: LocalizedStringKey {
        switch self {
        case .insufficient: "Insufficient"
        case .low: "Low"
        case .moderate: "Moderate"
        }
    }
}


private extension AnalysisEstimate.Scale {
    var isProbabilityDifference: Bool {
        self == .probabilityDifference || self == .ratingThresholdProbabilityDifference
    }
}

private extension AnalysisModel {
    var description: LocalizedStringKey {
        switch self {
        case .caffeineLinearV1: "Single-input linear association"
        case .numericLinearV1: "Numeric linear regression"
        case .binaryLogisticV1: "Logistic regression for daily yes/no outcomes"
        case .countLogLinearV1: "Poisson regression for daily counts"
        case .ratingThresholdLinearV1: "Linear regression with rating thresholds"
        case .numericInteractionV1: "Numeric linear regression with an interaction"
        case .categoryEventLogisticV1: "Logistic regression for a selected category"
        }
    }
}

private extension AnalysisEvidence.Reason {
    func description(isSleepDuration: Bool, isYesNoOutput: Bool) -> LocalizedStringKey {
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
        case .defaultOnlyOutput:
            isYesNoOutput ? "Every paired yes/no output comes from a default." : "Every paired output value comes from a default."
        case .lowVariationOutput:
            isYesNoOutput ? "Recorded output days all have the same yes/no value." : "Recorded output counts do not vary on paired days."
        case .sparseObservedCountOutput: "Too few recorded output counts show repeated variation and nonzero counts."
        case .countModelUnavailable: "The count model could not estimate a stable association. Some input values may only occur with zero output counts."
        case .countModelLimitations: "The model assumes a constant proportional change for each reported comparison. Longer dependence, unmeasured variables, and default values can affect the estimate."
        case .sparseObservedRatingOutput: "The output needs at least six recorded paired days on each side of its rating threshold."
        case .sparseObservedRatingInputs: "These inputs each need at least six recorded paired days on each side of their rating thresholds."
        case .ratingThresholdLimitations: "The estimate summarizes the selected rating groups. Longer dependence, unmeasured variables, and default values can affect it."
        case .sparseCategoryInputs: "Each selected input category needs at least six recorded days among the pairs."
        case .sparseCategoryOutput(let days): "The selected outcome and all other outcomes combined each need at least \(days) recorded days."
        case .sparseCategoryEventByInput: "Each input category needs at least six pairs with the recorded event and six with other recorded outcomes."
        case .categoryEventModelUnavailable: "The model could not estimate stable odds. Some inputs may nearly or completely predict the outcome."
        case .categoryEventModelLimitations: "The model estimates the odds of the selected outcome versus all other categories. Longer dependence, unmeasured variables, and defaults can affect the estimate."
        case .categoryModelLimitations: "Category contrasts use paired days with the selected input levels. Longer dependence, unmeasured variables, and defaults can affect the estimate."
        case .sparseObservedBinaryOutput: "There are too few recorded Yes or No output days for this model."
        case .sparseBinaryCombinations: "Some combinations of Yes and No have fewer than six days when every value was recorded."
        case .binaryContrastUnavailable: "Too few paired days support the reported increase within this input’s observed range."
        case .binaryModelUnavailable: "The yes/no model could not estimate a stable association. Some input values may occur with only one output answer."
        case .binaryModelLimitations: "Longer dependence, unmeasured variables, and default values can affect the estimated probability difference."
        case .adjustedModelLimitations: "Evidence is limited to this history and the variables included in the model."
        case .collinearInputs: "These inputs vary together too closely to estimate their separate associations."
        case .defaultOnlyInputs: "These inputs only have defaults on paired days."
        case .lowVariationInputs: "These inputs vary too little on paired days."
        case .poorlyRepresentedInteraction: "Too few fully recorded windows support the lower and higher combinations."
        }
    }

    var affectedInputs: Set<AnalysisSeriesID> {
        switch self {
        case .collinearInputs(let inputs), .defaultOnlyInputs(let inputs), .lowVariationInputs(let inputs),
             .sparseCategoryInputs(let inputs), .sparseCategoryEventByInput(let inputs),
             .sparseBinaryCombinations(let inputs), .binaryContrastUnavailable(let inputs),
             .sparseObservedRatingInputs(let inputs): inputs
        default: []
        }
    }
}

private extension AnalysisResult {
    var interactionInputs: (focal: AnalysisModeledInput, moderator: AnalysisModeledInput)? {
        guard let pair = configuration.interaction,
              let focal = modeledInputs.first(where: { $0.series == pair.focal }),
              let moderator = modeledInputs.first(where: { $0.series == pair.moderator }) else { return nil }
        return (focal, moderator)
    }
}
