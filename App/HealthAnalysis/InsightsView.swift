import HealthAnalysisCore
import SwiftUI

struct InsightsView: View {
    let application: HealthAnalysisApplication
    let openExplore: () -> Void
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        List {
            if application.firstUse.step != .complete {
                Section {
                    NavigationLink("Get started") {
                        FirstUseView(application: application, onFinish: openExplore)
                    }
                }
            }
            SavedAnalysisListSection(application: application, followingOnly: true)
            Section {
                discoveryRows
            } header: {
                Text("Discovered for you")
            } footer: {
                if let omitted = application.discovery.report?.omittedInputCount, omitted > 0 {
                    Text("Discovery uses the first four enabled inputs. \(omitted) enabled inputs are outside this search.")
                }
            }
            LatestHealthMeasurementsSection(history: application.healthMeasurements)
        }
    }

    @ViewBuilder
    private var discoveryRows: some View {
        let activity = application.discovery
        if activity.isSearching {
            ProgressView("Searching for associations…")
        }
        if let status = activity.unavailableStatus {
            Text(status.message(familySize: 0))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("discovery.unavailable")
        }
        if application.discoveryIsStale && activity.unavailableStatus == nil {
            Text("This search used earlier data or selections.")
                .foregroundStyle(.secondary)
        }
        if let report = activity.report {
            if report.findings.isEmpty && activity.unavailableStatus == nil && !activity.isSearching {
                Text(report.status.message(familySize: report.candidates.count))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("discovery.empty")
            }
            ForEach(report.findings) { finding in
                NavigationLink {
                    AnalysisResultScreen(application: application, configuration: finding.configuration, discovery: finding.completed)
                } label: {
                    DiscoveryRow(application: application, finding: finding)
                }
                .accessibilityIdentifier("discovery.open")
            }
        }
        NavigationLink("Discovery variables") {
            discoveryVariables
        }
        if case .healthHistoryUnavailable = activity.unavailableStatus {
            Button("Retry Health check") {
                Task { await application.healthMeasurements.refresh() }
            }
            .disabled(application.healthMeasurements.readState == .loading)
        } else if activity.report?.candidates.isEmpty == false {
            Button("Search again") {
                Task {
                    await application.refreshDiscoveries(timeZone: timeZone)
                }
            }
                .disabled(activity.isSearching)
        }
    }

    private var discoveryVariables: some View {
        Form {
            Section("Inputs") {
                ForEach(application.discoveryInputSeries, id: \.self) { series in
                    discoveryToggle(series)
                }
            }
            Section("Outputs") {
                ForEach(application.discoveryOutputSeries, id: \.self) { series in
                    discoveryToggle(series)
                }
            }
            Section("Search scope") {
                Text("Discovery tests up to four enabled daily quantities against resting heart rate and sleep duration over 1, 7, and 30 days.")
                Text("Use Explore for counts, yes/no values, ratings, categories, clock times, workout and running measurements, Health inputs, and daily-log outputs.")
                Text("HRV analysis requires verification of the original measurement and summary.")
            }
        }
        .navigationTitle("Discovery variables")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func discoveryToggle(_ series: AnalysisSeriesID) -> some View {
        Toggle(isOn: Binding {
            !application.discovery.disabledSeries.contains(series)
        } set: { enabled in
            application.discovery.setEnabled(enabled, for: series)
        }) {
            application.analysisSeriesTitle(series)
        }
    }
}

private struct DiscoveryRow: View {
    let application: HealthAnalysisApplication
    let finding: DiscoveryFinding

    private var result: AnalysisResult { finding.completed.result }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            title.font(.headline)
            effect
            Text(result.configuration.behaviorWindow.title)
            if let selection = finding.completed.discovery {
                Text("Exploratory · Low confidence after screening \(selection.familySize) comparisons")
            }
            Text("\(result.coverage.usableDates.count) paired days")
            Text("Updated \(finding.completed.updatedAt, format: .dateTime.month().day().year().hour().minute())")
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var title: Text {
        let output = application.analysisSeriesTitle(finding.configuration.output)
        guard let contrast = finding.completed.discovery?.contrast else { return output }
        switch contrast {
        case .input(let series):
            let input = application.analysisSeriesTitle(series)
            if let adjustment = finding.configuration.adjustmentInputs.first {
                return Text("\(output) with \(input), accounting for \(application.analysisSeriesTitle(adjustment))")
            }
            return Text("\(output) with \(input)")
        case .interaction(let pair):
            let focal = application.analysisSeriesTitle(pair.focal)
            let moderator = application.analysisSeriesTitle(pair.moderator)
            return Text("\(output) with \(focal) across \(moderator)")
        }
    }

    @ViewBuilder
    private var effect: some View {
        switch finding.completed.discovery?.contrast {
        case .input(let series):
            if let estimate = result.estimates.first(where: { $0.input == series }),
               let input = result.modeledInputs.first(where: { $0.series == series }) {
                estimateLabel(estimate, input: input, isSleepDuration: result.configuration.output.isSleepDuration)
            }
        case .interaction:
            if let comparison = result.interaction {
                let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
                if result.configuration.output.isSleepDuration {
                    Text("\(comparison.difference * 60, format: format) minutes difference between conditions")
                } else {
                    Text("\(comparison.difference, format: format) bpm difference between conditions")
                }
            }
        case nil:
            EmptyView()
        }
    }
}

private extension DiscoveryReport.Status {
    func message(familySize: Int) -> LocalizedStringKey {
        switch self {
        case .noEnabledInputs: "Add or enable a daily quantity to search for associations."
        case .noEnabledOutputs: "Enable an output to search for associations."
        case .noReadableOutputs: "There are no readable outputs for discovery."
        case .chooseOutputSource: "Choose a preferred source in Data to search this history."
        case .manualLogUnavailable: "Couldn’t open the daily log for discovery."
        case .healthHistoryUnavailable(let failure): failure.message
        case .healthHistoryLoading: "Discovery is waiting for the Health check."
        case .insufficientModelEvidence: "Discovery needs more paired days with enough variation to estimate an association."
        case .insufficientBlockEvidence: "Discovery needs recorded observations spread across five parts of the past year."
        case .noFindings: "None of the \(familySize) comparisons met the exploratory evidence threshold."
        case .findings: "There are exploratory findings."
        }
    }
}
