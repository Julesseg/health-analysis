import HealthAnalysisCore
import SwiftUI

struct ExploreView: View {
    let application: HealthAnalysisApplication
    private let editing: SavedAnalysis?
    @Environment(\.timeZone) private var timeZone

    @State private var output: AnalysisSeriesID?
    @State private var inputs: [AnalysisSeriesID]
    @State private var adjustments: [AnalysisSeriesID]
    @State private var behaviorWindow: AnalysisBehaviorWindow
    @State private var history: AnalysisPeriod
    @State private var interaction: AnalysisInteraction?
    @State private var analysisTimeZone: TimeZone
    @State private var categoryOutputEvent: TrackingCategory.ID?
    @State private var categoryInputSelections: [AnalysisSeriesID: CategoryContrastSelection]

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
        _categoryOutputEvent = State(initialValue: editing?.configuration.categories?.outputEvent)
        _categoryInputSelections = State(initialValue: editing?.configuration.categories?.inputContrasts.mapValues {
            CategoryContrastSelection(reference: $0.reference, comparison: $0.comparison)
        } ?? [:])
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

    private var categoryOutput: AnalysisVariable? {
        variables.first { $0.id == output && !$0.categories.isEmpty }
    }

    private var categoryInputs: [AnalysisVariable] {
        (inputs + adjustments).compactMap { id in
            variables.first { $0.id == id && !$0.categories.isEmpty }
        }
    }

    private var usesCategories: Bool { categoryOutput != nil || !categoryInputs.isEmpty }
    private var allowsLongerWindowsAndInteractions: Bool { !usesCounts && !usesCategories }

    private var configuration: AnalysisConfiguration? {
        guard let output, !inputs.isEmpty else { return nil }
        var configuration = editing?.configuration ?? .init(output: output, inputs: inputs)
        configuration.output = output
        configuration.inputs = inputs
        configuration.adjustmentInputs = adjustments
        configuration.behaviorWindow = allowsLongerWindowsAndInteractions ? behaviorWindow : .precedingDay
        configuration.history = history
        configuration.interaction = allowsLongerWindowsAndInteractions ? interaction : nil
        configuration.timeZone = analysisTimeZone
        if usesCategories {
            var contrasts: [AnalysisSeriesID: AnalysisCategoryContrast] = [:]
            for input in categoryInputs {
                guard let contrast = categoryInputSelections[input.id]?.contrast(in: input.categories) else { return nil }
                contrasts[input.id] = contrast
            }
            if let categoryOutput, !categoryOutput.categories.contains(where: { $0.id == categoryOutputEvent }) {
                return nil
            }
            configuration.categories = .init(
                inputContrasts: contrasts, outputEvent: categoryOutput == nil ? nil : categoryOutputEvent
            )
        } else {
            configuration.categories = nil
        }
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
                Picker("Output", selection: Binding(
                    get: { output },
                    set: { selection in
                        if selection != output { categoryOutputEvent = nil }
                        output = selection
                    }
                )) {
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
                    if let output, !outputs.contains(where: { $0.id == output }) {
                        application.analysisSeriesTitle(output).tag(output as AnalysisSeriesID?)
                    }
                }
                .accessibilityIdentifier("explore.output")
                .onChange(of: output) { _, selected in
                    inputs.removeAll { $0 == selected }
                    adjustments.removeAll { $0 == selected }
                }

                if let categoryOutput {
                    Picker("Output event", selection: $categoryOutputEvent) {
                        Text("Choose category").tag(nil as TrackingCategory.ID?)
                        ForEach(categoryOutput.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .accessibilityIdentifier("explore.category.event")
                }

                NavigationLink {
                    ExploreInputSelection(
                        title: "Inputs", choices: inputChoices,
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
                if inputs.count >= 2 && allowsLongerWindowsAndInteractions {
                    NavigationLink {
                        ExploreInteractionSelection(application: application, inputs: inputs, interaction: $interaction)
                    } label: {
                        LabeledContent("Interaction") { interactionSummary }
                    }
                    .accessibilityLabel("Interaction")
                    .accessibilityValue(interactionSummary)
                    .accessibilityIdentifier("explore.interaction")
                }
                ExploreTemporalControls(
                    behaviorWindow: $behaviorWindow, history: $history, allowsLongerWindows: allowsLongerWindowsAndInteractions
                )
            } footer: {
                if inputChoices.isEmpty {
                    Text("Add a supported daily tracking variable in Settings to choose another input.")
                }
                if usesCategories {
                    Text("Category analyses use the complete preceding day.")
                    Text("Interactions with categories are unavailable.")
                    if categoryOutput != nil {
                        Text("The model estimates the odds of the selected output category versus all other categories.")
                    }
                } else if usesCounts {
                    Text("Count analyses use the complete preceding day.")
                    Text("Interactions with counts are unavailable.")
                }
            }

            ForEach(categoryInputs) { input in
                Section {
                    CategoryContrastFields(
                        categories: input.categories,
                        selection: Binding(
                            get: { categoryInputSelections[input.id, default: CategoryContrastSelection()] },
                            set: { categoryInputSelections[input.id] = $0 }
                        )
                    )
                } header: {
                    Text(input.name)
                } footer: {
                    Text("Choose two different categories. Only days with either selected category can be paired.")
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
                Section {
                    NavigationLink("Suggested questions") {
                        AnalysisPresetsView(application: application, timeZone: timeZone, onSelect: applyPreset)
                    }
                }
                SavedAnalysisListSection(application: application)
            }
        }
    }

    private func applyPreset(_ preset: AnalysisConfiguration) {
        output = preset.output
        inputs = preset.inputs
        adjustments = preset.adjustmentInputs
        interaction = preset.interaction
        behaviorWindow = preset.behaviorWindow
        history = preset.history
        analysisTimeZone = preset.timeZone
        categoryOutputEvent = preset.categories?.outputEvent
        categoryInputSelections = preset.categories?.inputContrasts.mapValues {
            CategoryContrastSelection(reference: $0.reference, comparison: $0.comparison)
        } ?? [:]
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
