import Charts
import HealthAnalysisCore
import SwiftUI

struct ExploreResultView: View {
    let application: HealthAnalysisApplication
    let configuration: AnalysisConfiguration
    let inputName: String

    @State private var run: Result<AnalysisResult, AnalysisRunFailure>?

    private var isSleepDuration: Bool { configuration.output.isSleepDuration }

    var body: some View {
        List {
            switch run {
            case .success(let result):
                findings(result)
                evidence(result)
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
        Section {
            if let estimate = result.estimates.first {
                Text(estimate.finding.description(isSleepDuration: isSleepDuration))
                    .font(.headline)
                Group {
                    if isSleepDuration {
                        Text("\(estimate.difference * 60, format: estimateNumber) minutes per \(estimate.inputIncrement, format: .number) mg more caffeine")
                    } else {
                        Text("\(estimate.difference, format: estimateNumber) bpm per \(estimate.inputIncrement, format: .number) mg more caffeine")
                    }
                }
                .monospacedDigit()
                LabeledContent("Dependence-adjusted interval") {
                    Text(intervalLabel(estimate, isSleepDuration: isSleepDuration))
                }
                .accessibilityIdentifier("explore.uncertainty")
                EstimateChart(estimate: estimate, isSleepDuration: isSleepDuration)
                if estimate.finding == .nearZero {
                    Group {
                        if isSleepDuration {
                            Text("The full interval is within 15 minutes of zero per 100 mg of caffeine.")
                        } else {
                            Text("The full interval is within 1 bpm of zero per 100 mg of caffeine.")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("There isn’t enough evidence to estimate this association.")
                    .font(.headline)
            }
            if result.lastHealthReadFailure != nil {
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
            ForEach(result.evidence.reasons, id: \.self) { reason in
                Text(reason.description(isSleepDuration: isSleepDuration))
            }
            if let days = result.evidence.dependenceLagDays {
                Text("The interval allows for dependence across up to \(days) calendar days.")
            }
            Text("This comparison uses one input. Other variables may also be associated with the output.")
                .foregroundStyle(.secondary)
        }
    }

    private func coverage(_ result: AnalysisResult) -> some View {
        Section("Coverage") {
            ExploreTemporalSummary(configuration: result.configuration)
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
            if result.configuration.behaviorWindow != .precedingDay {
                LabeledContent("Distinct behavior days") {
                    Text(result.coverage.distinctBehaviorDayCount, format: .number)
                }
                LabeledContent("Nonoverlapping windows") {
                    Text(result.coverage.nonOverlappingWindowCount, format: .number)
                }
            }
            LabeledContent("Paired days using a default") {
                Text(result.evidence.defaultDayCount, format: .number)
            }
            if let source = result.outputSource {
                LabeledContent("Output source") {
                    Text(source.name)
                }
            }
            NavigationLink("Usable dates and gaps") {
                ExploreCoverageView(result: result, inputName: inputName)
            }
            measurementsLink
        }
    }

    private var measurementsLink: some View {
        NavigationLink("Inspect Health measurements") {
            HealthMeasurementHistoryView(
                history: application.healthMeasurements, presentation: isSleepDuration ? .sleep : .restingHeartRate
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
    let isSleepDuration: Bool

    private var scale: Double { isSleepDuration ? 60 : 1 }
    private var lower: Double { estimate.interval.lowerBound * scale }
    private var upper: Double { estimate.interval.upperBound * scale }
    private var difference: Double { estimate.difference * scale }
    private var axisLabel: LocalizedStringKey {
        isSleepDuration ? "Difference in sleep duration (minutes)" : "Difference in resting heart rate (bpm)"
    }

    var body: some View {
        Chart {
            RuleMark(x: .value("Zero difference", 0.0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
            RuleMark(
                xStart: .value("Lower limit", lower),
                xEnd: .value("Upper limit", upper),
                y: .value("Estimate", "Caffeine")
            )
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            .foregroundStyle(Color.accentColor)
            PointMark(
                x: .value("Estimated difference", difference),
                y: .value("Estimate", "Caffeine")
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartXScale(domain: min(-1, lower)...max(1, upper))
        .chartXAxisLabel(axisLabel, position: .bottom, alignment: .center)
        .chartYAxis(.hidden)
        .frame(height: 95)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated difference and uncertainty")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("explore.estimateChart")
    }

    private var accessibilityValue: Text {
        let interval = intervalLabel(estimate, isSleepDuration: isSleepDuration)
        if isSleepDuration {
            return Text("\(difference, format: estimateNumber) minutes. Dependence-adjusted interval \(interval).")
        }
        return Text("\(difference, format: estimateNumber) beats per minute. Dependence-adjusted interval \(interval).")
    }
}

private struct ExploreCoverageView: View {
    let result: AnalysisResult
    let inputName: String

    private var timeZone: TimeZone { result.configuration.timeZone }

    var body: some View {
        List {
            Section("Question") {
                LabeledContent {
                    Text(inputName)
                } label: {
                    Text("Caffeine quantity")
                }
                LabeledContent("Output") {
                    Text(result.configuration.output.isSleepDuration ? "Sleep duration" : "Resting heart rate")
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
                if result.configuration.output.isSleepDuration {
                    Text("Each recorded wake date uses its longest completed sleep episode. The caffeine window uses complete days before the episode began.")
                } else {
                    Text("The caffeine window uses complete local days before the resting heart rate sample began.")
                }
                if result.configuration.behaviorWindow != .precedingDay {
                    Text("Caffeine amounts are added across the selected window.")
                }
                if result.configuration.history != .fullHistory {
                    Text("History limits output dates. Earlier caffeine can still complete a window.")
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

private func intervalLabel(_ estimate: AnalysisEstimate, isSleepDuration: Bool) -> String {
    if isSleepDuration {
        return String(localized: "\(estimate.interval.lowerBound * 60, format: estimateNumber) to \(estimate.interval.upperBound * 60, format: estimateNumber) minutes")
    }
    return String(localized: "\(estimate.interval.lowerBound, format: estimateNumber) to \(estimate.interval.upperBound, format: estimateNumber) bpm")
}

private extension AnalysisSeriesID {
    var isSleepDuration: Bool {
        if case .health(metric: .sleepAnalysis, _) = self { return true }
        return false
    }
}

private extension AnalysisEstimate.Finding {
    func description(isSleepDuration: Bool) -> LocalizedStringKey {
        switch (self, isSleepDuration) {
        case (.higher, false): "Higher caffeine amounts were associated with higher resting heart rate."
        case (.lower, false): "Higher caffeine amounts were associated with lower resting heart rate."
        case (.higher, true): "Higher caffeine amounts were associated with longer sleep."
        case (.lower, true): "Higher caffeine amounts were associated with shorter sleep."
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

private extension AnalysisEvidence.Reason {
    func description(isSleepDuration: Bool) -> LocalizedStringKey {
        switch self {
        case .inadequateCoverage: "This comparison needs at least 42 paired days."
        case .limitedNonOverlappingWindows: "This comparison needs at least six windows that share no behavior days."
        case .overlappingBehaviorWindows: "Some windows share behavior days, which limits confidence in this result."
        case .noObservedInputs: "Every caffeine day in the paired windows comes from a default."
        case .limitedInputVariation: "Caffeine amounts varied too little across paired days."
        case .uncertaintyUnavailable: "The paired values could not support a usable uncertainty interval."
        case .limitedHistory: "The analysis uses fewer than 90 paired days."
        case .sparseCoverage: "Fewer than three quarters of days in the usable history had a pair."
        case .manyDefaults: "More than one quarter of paired days used an assumed caffeine amount."
        case .wideInterval:
            isSleepDuration
                ? "The uncertainty interval spans more than 30 minutes per 100 mg of caffeine."
                : "The uncertainty interval spans more than 2 bpm per 100 mg of caffeine."
        case .indeterminateInterval: "The interval is compatible with a near-zero association and with a larger difference."
        case .adequateCoverageAndPrecision: "The analysis has at least 90 paired days, good overlap, limited default use, and a narrow interval."
        }
    }
}

private extension AnalysisRunFailure {
    var description: LocalizedStringKey {
        switch self {
        case .unsupportedConfiguration: "This analysis configuration is unavailable."
        case .inputUnavailable: "The selected caffeine quantity is unavailable."
        case .manualLogUnavailable: "Couldn’t open the daily log."
        case .chooseOutputSource: "Choose a preferred source for this output in Health measurements."
        case .healthHistoryUnavailable: "Couldn’t use Health history. Check Health measurements and try again."
        case .healthHistoryLoading: "Health measurements are still being checked. Try again when the check finishes."
        }
    }
}
