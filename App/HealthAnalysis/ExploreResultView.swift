import Charts
import HealthAnalysisCore
import SwiftUI

struct ExploreResultView: View {
    let application: HealthAnalysisApplication
    let configuration: AnalysisConfiguration
    let inputName: String

    @State private var run: Result<AnalysisResult, AnalysisRunFailure>?

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
                Text(estimate.finding.description)
                    .font(.headline)
                Text("\(estimate.difference, format: estimateNumber) bpm per \(estimate.inputIncrement, format: .number) mg more caffeine")
                    .monospacedDigit()
                LabeledContent("Approximate 95% uncertainty interval") {
                    Text(intervalLabel(estimate))
                }
                EstimateChart(estimate: estimate)
                if estimate.finding == .nearZero {
                    Text("The full interval is within 1 bpm of zero per 100 mg of caffeine.")
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
                Text(reason.description)
            }
            if let days = result.evidence.dependenceLagDays {
                Text("The interval accounts for dependence across up to \(days) calendar days.")
            }
            Text("This comparison uses one input. Other variables may also be associated with resting heart rate.")
                .foregroundStyle(.secondary)
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
                ExploreCoverageView(result: result, inputName: inputName)
            }
            measurementsLink
        }
    }

    private var measurementsLink: some View {
        NavigationLink("Inspect Health measurements") {
            HealthMeasurementHistoryView(history: application.healthMeasurements)
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

    var body: some View {
        Chart {
            RuleMark(x: .value("Zero difference", 0.0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
            RuleMark(
                xStart: .value("Lower limit", estimate.interval.lowerBound),
                xEnd: .value("Upper limit", estimate.interval.upperBound),
                y: .value("Estimate", "Caffeine")
            )
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            .foregroundStyle(Color.accentColor)
            PointMark(
                x: .value("Estimated difference", estimate.difference),
                y: .value("Estimate", "Caffeine")
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartXScale(domain: min(-1, estimate.interval.lowerBound)...max(1, estimate.interval.upperBound))
        .chartXAxisLabel("Difference in resting heart rate (bpm)", position: .bottom, alignment: .center)
        .chartYAxis(.hidden)
        .frame(height: 95)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated difference and uncertainty")
        .accessibilityValue(
            Text("\(estimate.difference, format: estimateNumber) beats per minute. Approximate 95% interval: \(intervalLabel(estimate)).")
        )
        .accessibilityIdentifier("explore.estimateChart")
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
                Text("Each pair uses caffeine from the complete local day before the resting heart rate sample began.")
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
        case .higher: "Higher caffeine amounts were associated with higher resting heart rate."
        case .lower: "Higher caffeine amounts were associated with lower resting heart rate."
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

private extension AnalysisEvidence.Reason {
    var description: LocalizedStringKey {
        switch self {
        case .inadequateCoverage: "This comparison needs at least 42 paired days."
        case .noObservedInputs: "Every paired caffeine amount comes from a default."
        case .limitedInputVariation: "Caffeine amounts varied too little across paired days."
        case .uncertaintyUnavailable: "The paired values could not support a usable uncertainty interval."
        case .limitedHistory: "The analysis uses fewer than 90 paired days."
        case .sparseCoverage: "Fewer than three quarters of days in the usable history had a pair."
        case .manyDefaults: "More than one quarter of paired days used an assumed caffeine amount."
        case .wideInterval: "The uncertainty interval spans more than 2 bpm per 100 mg of caffeine."
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
        case .chooseOutputSource: "Choose a preferred resting heart rate source in Health measurements."
        case .healthHistoryUnavailable: "Couldn’t use Health history. Check Health measurements and try again."
        case .healthHistoryLoading: "Health measurements are still being checked. Try again when the check finishes."
        }
    }
}
