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
    @State private var analysisTimeZone: TimeZone

    init(application: HealthAnalysisApplication, editing: SavedAnalysis? = nil) {
        self.application = application
        self.editing = editing
        _output = State(initialValue: editing?.configuration.output)
        _inputs = State(initialValue: editing?.configuration.inputs ?? [])
        _adjustments = State(initialValue: editing?.configuration.adjustmentInputs ?? [])
        _behaviorWindow = State(initialValue: editing?.configuration.behaviorWindow ?? .precedingDay)
        _history = State(initialValue: editing?.configuration.history ?? .fullHistory)
        _analysisTimeZone = State(initialValue: editing?.configuration.timeZone ?? .current)
    }

    private var variables: [AnalysisVariable] { application.analysisVariables }

    private var inputChoices: [AnalysisVariable] {
        variables.filter { $0.supportsInput && $0.id != output }
    }

    private var adjustmentChoices: [AnalysisVariable] {
        inputChoices.filter { !inputs.contains($0.id) }
    }

    private var usesCounts: Bool {
        let selected = inputs + adjustments + [output].compactMap { $0 }
        return variables.contains { selected.contains($0.id) && $0.kind == .tracked(.count) }
    }

    private var configuration: AnalysisConfiguration? {
        guard let output, !inputs.isEmpty else { return nil }
        var configuration = editing?.configuration ?? .init(output: output, inputs: inputs)
        configuration.output = output
        configuration.inputs = inputs
        configuration.adjustmentInputs = adjustments
        configuration.behaviorWindow = behaviorWindow
        configuration.history = history
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
                    let outputs = variables.filter(\.supportsOutput)
                    ForEach(outputs) { choice in
                        switch choice.id {
                        case .health:
                            application.analysisSeriesTitle(choice.id).tag(choice.id as AnalysisSeriesID?)
                        default:
                            choice.analysisChoiceLabel.tag(choice.id as AnalysisSeriesID?)
                        }
                    }
                    if let savedOutput = editing?.configuration.output, !outputs.contains(where: { $0.id == savedOutput }) {
                        application.analysisSeriesTitle(savedOutput).tag(savedOutput as AnalysisSeriesID?)
                    }
                }
                .accessibilityIdentifier("explore.output")
                .onChange(of: output) { _, selected in
                    inputs.removeAll { $0 == selected }
                    adjustments.removeAll { $0 == selected }
                }

                NavigationLink {
                    ExploreInputSelection(
                        title: "Inputs", choices: inputChoices,
                        selection: Binding(
                            get: { inputs },
                            set: { selected in
                                inputs = selected
                                adjustments.removeAll { selected.contains($0) }
                            }
                        )
                    )
                } label: {
                    LabeledContent("Inputs") { selectionSummary(inputs) }
                }
                .disabled(inputChoices.isEmpty)
                .accessibilityLabel("Inputs")
                .accessibilityValue(selectionSummary(inputs))
                .accessibilityIdentifier("explore.inputs")

                NavigationLink {
                    ExploreInputSelection(
                        title: "Account for", choices: adjustmentChoices,
                        selection: $adjustments, showsSuggestions: true
                    )
                } label: {
                    LabeledContent("Account for") { selectionSummary(adjustments) }
                }
                .disabled(adjustmentChoices.isEmpty)
                .accessibilityLabel("Account for")
                .accessibilityValue(selectionSummary(adjustments))
                .accessibilityIdentifier("explore.adjustments")
                ExploreTemporalControls(
                    behaviorWindow: $behaviorWindow, history: $history, allowsLongerWindows: !usesCounts
                )
            } footer: {
                if inputChoices.isEmpty {
                    Text("Add a daily quantity or count in Settings to choose another variable.")
                }
                if usesCounts {
                    Text("Count analyses use the complete preceding day.")
                    Text("Interactions with counts are unavailable.")
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
        .onChange(of: usesCounts) { _, includesCounts in
            if includesCounts { behaviorWindow = .precedingDay }
        }
    }

    private func selectionSummary(_ selected: [AnalysisSeriesID]) -> Text {
        switch selected.count {
        case 0: Text("None")
        case 1: application.analysisSeriesTitle(selected[0])
        default: Text("\(selected.count) selected")
        }
    }
}

private struct ExploreInputSelection: View {
    let title: LocalizedStringKey
    let choices: [AnalysisVariable]
    @Binding var selection: [AnalysisSeriesID]
    var showsSuggestions = false

    var body: some View {
        Form {
            Section {
                ForEach(choices) { choice in
                    let series = choice.id
                    Toggle(
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
                    ) {
                        choice.analysisChoiceLabel
                    }
                }
            } header: {
                if showsSuggestions { Text("Suggested adjustments") }
            } footer: {
                if showsSuggestions {
                    Text("Choose other logged variables to account for in this analysis.")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
