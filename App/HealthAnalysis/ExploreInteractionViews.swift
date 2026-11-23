import Charts
import HealthAnalysisCore
import SwiftUI

struct ExploreInteractionSelection: View {
    let application: HealthAnalysisApplication
    let inputs: [AnalysisSeriesID]
    @Binding var interaction: AnalysisInteraction?

    var body: some View {
        Form {
            Section {
                Picker("Association for", selection: focal) {
                    Text("None").tag(nil as AnalysisSeriesID?)
                    ForEach(inputs, id: \.self) { series in
                        application.analysisSeriesTitle(series).tag(series as AnalysisSeriesID?)
                    }
                }
                .accessibilityIdentifier("explore.interaction.focal")
                if let pair = interaction {
                    Picker("Compare across", selection: moderator(for: pair)) {
                        ForEach(inputs.filter { $0 != pair.focal }, id: \.self) { series in
                            application.analysisSeriesTitle(series).tag(series)
                        }
                    }
                    .accessibilityIdentifier("explore.interaction.moderator")
                }
            } footer: {
                Text("Compare the association for one input at lower and higher values of another.")
            }
        }
        .navigationTitle("Interaction")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var focal: Binding<AnalysisSeriesID?> {
        Binding(
            get: { interaction?.focal },
            set: { selected in
                guard let selected, let alternative = inputs.first(where: { $0 != selected }) else {
                    interaction = nil
                    return
                }
                let current = interaction?.moderator
                let other = current == selected ? alternative : current ?? alternative
                interaction = .init(focal: selected, moderator: other)
            }
        )
    }

    private func moderator(for pair: AnalysisInteraction) -> Binding<AnalysisSeriesID> {
        Binding(
            get: { interaction?.moderator ?? pair.moderator },
            set: { interaction = .init(focal: pair.focal, moderator: $0) }
        )
    }
}

struct InteractionResultSection: View {
    let focal: AnalysisModeledInput
    let moderator: AnalysisModeledInput
    let estimate: AnalysisInteractionEstimate?
    let isSleepDuration: Bool
    @ScaledMetric private var chartHeight = 110.0

    private var scale: Double { isSleepDuration ? 60 : 1 }

    var body: some View {
        Section {
            if let estimate {
                Text(finding(estimate.finding))
                    .font(.headline)
                    .accessibilityIdentifier("explore.interaction.finding")
                Text("\(focal.name) from \(estimate.focalValues.lowerBound, format: .number) to \(estimate.focalValues.upperBound, format: .number) \(focal.unit)")
                condition(estimate.lowerCondition, level: .lower)
                condition(estimate.higherCondition, level: .higher)
                LabeledContent("Change from lower to higher condition") {
                    difference(estimate.difference)
                }
                LabeledContent("Dependence-adjusted interval for the change") {
                    Text(intervalLabel(estimate.interval))
                }
                .accessibilityIdentifier("explore.interaction.uncertainty")
                chart(estimate)
                Text("Each condition holds the other modeled inputs fixed.")
                    .foregroundStyle(.secondary)
            } else {
                Text("There isn’t enough evidence to compare these conditions.")
                    .font(.headline)
                    .accessibilityIdentifier("explore.interaction.finding")
            }
        } header: {
            Text("\(focal.name) across \(moderator.name)")
        }
    }

    private enum Level {
        case lower
        case higher

        var label: String {
            switch self {
            case .lower: String(localized: "Lower")
            case .higher: String(localized: "Higher")
            }
        }
    }

    private func condition(_ condition: AnalysisInteractionEstimate.Condition, level: Level) -> some View {
        VStack(alignment: .leading) {
            Text("\(moderator.name) at \(condition.moderatorValue, format: .number) \(moderator.unit) (\(level.label))")
            Text("\(difference(condition.difference)) (dependence-adjusted interval \(intervalLabel(condition.interval)))")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(level == .lower ? "explore.interaction.lower" : "explore.interaction.higher")
    }

    private func chart(_ estimate: AnalysisInteractionEstimate) -> some View {
        VStack {
            Chart {
                RuleMark(x: .value("Zero difference", 0.0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                marks(estimate.lowerCondition, level: .lower)
                marks(estimate.higherCondition, level: .higher)
            }
            .chartYScale(domain: [Level.lower.label, Level.higher.label])
            .chartXAxisLabel(axisLabel, position: .bottom, alignment: .center)
            .frame(height: chartHeight)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Adjusted condition estimates for \(focal.name) across \(moderator.name)"))
        .accessibilityValue(Text(finding(estimate.finding)))
        .accessibilityIdentifier("explore.interaction.chart")
    }

    @ChartContentBuilder
    private func marks(_ condition: AnalysisInteractionEstimate.Condition, level: Level) -> some ChartContent {
        RuleMark(
            xStart: .value("Lower limit", condition.interval.lowerBound * scale),
            xEnd: .value("Upper limit", condition.interval.upperBound * scale),
            y: .value("Condition", level.label)
        )
        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
        .foregroundStyle(Color.accentColor)
        PointMark(
            x: .value("Estimated difference", condition.difference * scale),
            y: .value("Condition", level.label)
        )
        .foregroundStyle(Color.accentColor)
    }

    private func finding(_ finding: AnalysisEstimate.Finding) -> LocalizedStringKey {
        switch finding {
        case .higher: "The estimated association is more positive at the higher condition."
        case .lower: "The estimated association is more negative at the higher condition."
        case .nearZero: "The estimated associations are similar across these conditions."
        case .uncertain: "The difference between the estimated associations is uncertain."
        }
    }

    private var axisLabel: LocalizedStringKey {
        isSleepDuration ? "Difference in sleep duration (minutes)" : "Difference in resting heart rate (bpm)"
    }

    private func difference(_ value: Double) -> Text {
        if isSleepDuration { Text("\(value * scale, format: interactionNumber) minutes") }
        else { Text("\(value, format: interactionNumber) bpm") }
    }

    private func intervalLabel(_ interval: ClosedRange<Double>) -> String {
        if isSleepDuration {
            return String(localized: "\(interval.lowerBound * scale, format: interactionNumber) to \(interval.upperBound * scale, format: interactionNumber) minutes")
        }
        return String(localized: "\(interval.lowerBound, format: interactionNumber) to \(interval.upperBound, format: interactionNumber) bpm")
    }
}

struct InteractionSupportRows: View {
    let support: AnalysisInteractionSupport

    var body: some View {
        LabeledContent("Paired windows with both interaction inputs fully recorded") {
            Text(support.explicitlyObservedPairDays, format: .number)
        }
        if !support.explicitDaysByCombination.isEmpty {
            Text("Each combination needs at least \(support.minimumDaysPerCombination) windows with both inputs fully recorded.")
            ForEach(AnalysisInteractionSupport.Combination.allCases, id: \.self) { combination in
                if let count = support.explicitDaysByCombination[combination] {
                    LabeledContent(combination.label) { Text(count, format: .number) }
                }
            }
        } else if support.explicitlyObservedPairDays > 0 {
            Text("These inputs varied too little across windows when both were fully recorded.")
        }
    }
}

private extension AnalysisInteractionSupport.Combination {
    var label: LocalizedStringKey {
        switch self {
        case .lowerFocalLowerModerator: "Lower input, lower condition"
        case .higherFocalLowerModerator: "Higher input, lower condition"
        case .lowerFocalHigherModerator: "Lower input, higher condition"
        case .higherFocalHigherModerator: "Higher input, higher condition"
        }
    }
}

private let interactionNumber = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
