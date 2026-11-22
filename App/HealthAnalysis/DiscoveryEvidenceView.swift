import HealthAnalysisCore
import SwiftUI

struct DiscoveryEvidenceView: View {
    let baseline: CompletedAnalysis
    let selection: DiscoverySelection
    let reassessment: DiscoveryReassessment?
    let application: HealthAnalysisApplication

    var body: some View {
        List {
            Section("Original discovery") {
                dateRow("Discovery cutoff", selection.cutoff, format: baseline.result.analysisDateFormat.hour().minute(),
                        identifier: "discovery.cutoff")
                evidenceDates(baseline.result, latestIdentifier: "discovery.original.latestPairedOutput")
                contrastRows(baseline.result)
                confidence(baseline.result)
                Text("The search screened \(selection.familySize) comparisons and checked the selected contrast across separate parts of the history.")
                LabeledContent("Search-adjusted p-value") {
                    let format = FloatingPointFormatStyle<Double>.number
                        .notation(selection.adjustedPValue < 0.001 ? .scientific : .automatic)
                        .precision(.significantDigits(2...3))
                    Text(selection.adjustedPValue, format: format)
                }
                Text("The model interval describes the fitted association. The search-adjusted p-value accounts for the screened comparisons.")
            }
            Section("Later evidence") {
                if let reassessment {
                    let result = reassessment.result
                    Text(reassessment.support.label).font(.headline)
                    if let latest = reassessment.latestEligibleOutputDate {
                        dateRow("Latest eligible output", latest, format: result.analysisDateFormat,
                                identifier: "discovery.latestEligibleOutput")
                    }
                    evidenceDates(result, latestIdentifier: "discovery.later.latestPairedOutput")
                    contrastRows(result)
                    confidence(result)
                    if result.coverage.outputDayCount > 0 {
                        NavigationLink("Later usable dates and gaps") {
                            AnalysisCoverageView(result: result, application: application)
                        }
                    }
                    Text("Reassessment requires fully recorded behavior windows after the cutoff. Dependence can persist across the cutoff, and repeated refreshes can reuse later observations.")
                } else {
                    Text("Subsequent-data support is unassessed.")
                }
            }
        }
        .navigationTitle("Discovery evidence")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func evidenceDates(_ result: AnalysisResult, latestIdentifier: String) -> some View {
        if let first = result.coverage.firstDate, let last = result.coverage.lastDate {
            LabeledContent("First paired output") {
                Text(first, format: result.analysisDateFormat)
            }
            dateRow("Latest paired output", last, format: result.analysisDateFormat, identifier: latestIdentifier)
        }
        LabeledContent("Paired days", value: result.coverage.usableDates.count.formatted())
    }

    private func dateRow(
        _ label: LocalizedStringKey, _ date: Date, format: Date.FormatStyle, identifier: String
    ) -> some View {
        let value = Text(date, format: format)
        return LabeledContent(label) { value }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func contrastRows(_ result: AnalysisResult) -> some View {
        let isSleep = result.configuration.output.isSleepDuration
        switch selection.contrast {
        case .input(let id):
            if let estimate = result.estimates.first(where: { $0.input == id }),
               let input = result.modeledInputs.first(where: { $0.series == id }) {
                LabeledContent("Estimated association") {
                    estimateLabel(estimate, input: input, isSleepDuration: isSleep)
                }
                LabeledContent("Dependence-adjusted interval") {
                    Text(intervalLabel(estimate, isSleepDuration: isSleep))
                }
            }
        case .interaction(let pair):
            if let estimate = result.interaction,
               let focal = result.modeledInputs.first(where: { $0.series == pair.focal }),
               let moderator = result.modeledInputs.first(where: { $0.series == pair.moderator }) {
                Text("\(focal.name) from \(estimate.focalValues.lowerBound, format: .number) to \(estimate.focalValues.upperBound, format: .number) \(focal.unit)")
                Text("\(moderator.name) from \(estimate.lowerCondition.moderatorValue, format: .number) to \(estimate.higherCondition.moderatorValue, format: .number) \(moderator.unit)")
                LabeledContent("Change from lower to higher condition") {
                    let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
                    if isSleep {
                        Text("\(estimate.difference * 60, format: format) minutes")
                    } else {
                        Text("\(estimate.difference, format: format) bpm")
                    }
                }
                LabeledContent("Dependence-adjusted interval") {
                    Text(numericAssociationIntervalLabel(estimate.interval, isSleepDuration: isSleep))
                }
            }
        }
    }

    private func confidence(_ result: AnalysisResult) -> some View {
        NavigationLink {
            AnalysisModelView(result: result, log: application.manualLog)
        } label: {
            LabeledContent("Model confidence") { Text(result.evidence.grade.description) }
        }
    }
}

extension DiscoveryReassessment.Support {
    var label: LocalizedStringKey {
        switch self {
        case .noLaterObservations: "No later outputs with a behavior window after the cutoff."
        case .insufficient: "There isn’t enough later evidence to estimate the selected comparison."
        case .sameDirection: "Later evidence points in the same direction."
        case .oppositeDirection: "Later evidence points in the opposite direction."
        case .nearZero: "The later estimate is close to zero."
        case .uncertain: "The later estimate is uncertain."
        }
    }
}
