import HealthAnalysisCore
import SwiftUI

struct ExploreView: View {
    let application: HealthAnalysisApplication
    private let editing: SavedAnalysis?

    @State private var output: AnalysisSeriesID?
    @State private var inputs: [AnalysisSeriesID]
    @State private var adjustments: [AnalysisSeriesID]
    @State private var behaviorWindow: AnalysisBehaviorWindow
    @State private var history: AnalysisPeriod
    @State private var interaction: AnalysisInteraction?
    @State private var analysisTimeZone: TimeZone

    init(application: HealthAnalysisApplication, editing: SavedAnalysis? = nil) {
        self.application = application
        self.editing = editing
        _output = State(initialValue: editing?.configuration.output)
        _inputs = State(initialValue: editing?.configuration.inputs ?? [])
        _adjustments = State(initialValue: editing?.configuration.adjustmentInputs ?? [])
        _behaviorWindow = State(initialValue: editing?.configuration.behaviorWindow ?? .precedingDay)
        _history = State(initialValue: editing?.configuration.history ?? .fullHistory)
        _interaction = State(initialValue: editing?.configuration.interaction)
        _analysisTimeZone = State(initialValue: editing?.configuration.timeZone ?? .current)
    }

    private var quantities: [TrackingQuantity] { application.analysisNumericQuantities }

    private var adjustmentChoices: [TrackingQuantity] {
        let inputIDs = inputs.compactMap { series -> UUID? in
            if case .manualQuantity(let id) = series { return id }
            return nil
        }
        return application.analysisAdjustmentSuggestions(excluding: inputIDs)
    }

    private var configuration: AnalysisConfiguration? {
        guard let output, !inputs.isEmpty else { return nil }
        var configuration = editing?.configuration ?? .init(output: output, inputs: inputs)
        configuration.output = output
        configuration.inputs = inputs
        configuration.adjustmentInputs = adjustments
        configuration.behaviorWindow = behaviorWindow
        configuration.history = history
        configuration.interaction = interaction
        configuration.timeZone = analysisTimeZone
        return configuration
    }

    var body: some View {
        Form {
            if !application.overview.hasReadableMeasurements && !application.overview.hasTrackingVariables {
                Section {
                    Text("No variables to explore")
                        .font(.headline)
                    Text("Explore uses readable measurements and manually tracked variables.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Output", selection: $output) {
                    Text("Choose output").tag(nil as AnalysisSeriesID?)
                    let restingHeartRate = AnalysisSeriesID.health(metric: .restingHeartRate)
                    let sleepDuration = AnalysisSeriesID.health(metric: .sleepAnalysis)
                    Text("Resting heart rate").tag(restingHeartRate as AnalysisSeriesID?)
                    Text("Sleep duration").tag(sleepDuration as AnalysisSeriesID?)
                    if let savedOutput = editing?.configuration.output,
                       savedOutput != restingHeartRate, savedOutput != sleepDuration {
                        application.analysisSeriesTitle(savedOutput).tag(savedOutput as AnalysisSeriesID?)
                    }
                }
                .accessibilityIdentifier("explore.output")

                NavigationLink {
                    ExploreQuantitySelection(
                        title: "Inputs", quantities: quantities,
                        selection: Binding(
                            get: { inputs },
                            set: { selected in
                                inputs = selected
                                adjustments.removeAll { selected.contains($0) }
                                if let pair = interaction,
                                   !selected.contains(pair.focal) || !selected.contains(pair.moderator) {
                                    interaction = nil
                                }
                            }
                        )
                    )
                } label: {
                    LabeledContent("Inputs") { selectionSummary(inputs) }
                }
                .disabled(quantities.isEmpty)
                .accessibilityLabel("Inputs")
                .accessibilityValue(selectionSummary(inputs))
                .accessibilityIdentifier("explore.inputs")

                NavigationLink {
                    ExploreQuantitySelection(
                        title: "Account for", quantities: adjustmentChoices,
                        selection: $adjustments, showsSuggestions: true
                    )
                } label: {
                    LabeledContent("Account for") { selectionSummary(adjustments) }
                }
                .disabled(adjustmentChoices.isEmpty)
                .accessibilityLabel("Account for")
                .accessibilityValue(selectionSummary(adjustments))
                .accessibilityIdentifier("explore.adjustments")
                if inputs.count >= 2 {
                    NavigationLink {
                        ExploreInteractionSelection(application: application, inputs: inputs, interaction: $interaction)
                    } label: {
                        LabeledContent("Interaction") { interactionSummary }
                    }
                    .accessibilityLabel("Interaction")
                    .accessibilityValue(interactionSummary)
                    .accessibilityIdentifier("explore.interaction")
                }
                ExploreTemporalControls(behaviorWindow: $behaviorWindow, history: $history)
            } footer: {
                if quantities.isEmpty {
                    Text("Add a daily quantity in Settings to choose an input.")
                }
            }

            Section {
                if let configuration {
                    NavigationLink("Analyze") {
                        AnalysisResultScreen(application: application, configuration: configuration, editing: editing?.id)
                            .id(configuration)
                    }
                } else {
                    Button("Analyze") {}
                        .disabled(true)
                }
            }

            if editing == nil {
                SavedAnalysisListSection(application: application)
            }
        }
    }

    private var interactionSummary: Text {
        guard let interaction else { return Text("None") }
        let focal = application.analysisSeriesTitle(interaction.focal)
        let moderator = application.analysisSeriesTitle(interaction.moderator)
        return Text("\(focal) across \(moderator)")
    }

    private func selectionSummary(_ selected: [AnalysisSeriesID]) -> Text {
        switch selected.count {
        case 0: Text("None")
        case 1: application.analysisSeriesTitle(selected[0])
        default: Text("\(selected.count) selected")
        }
    }
}

private struct ExploreQuantitySelection: View {
    let title: LocalizedStringKey
    let quantities: [TrackingQuantity]
    @Binding var selection: [AnalysisSeriesID]
    var showsSuggestions = false

    var body: some View {
        Form {
            Section {
                ForEach(quantities) { quantity in
                    let series = AnalysisSeriesID.manualQuantity(quantity.id)
                    Toggle(
                        "\(quantity.name) (\(quantity.unit))",
                        isOn: Binding(
                            get: { selection.contains(series) },
                            set: { selected in
                                if selected && !selection.contains(series) {
                                    selection.append(series)
                                } else if !selected {
                                    selection.removeAll { $0 == series }
                                }
                            }
                        )
                    )
                }
            } header: {
                if showsSuggestions { Text("Suggested adjustments") }
            } footer: {
                if showsSuggestions {
                    Text("These are other logged quantities. Choose the ones you want to account for in this analysis.")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
