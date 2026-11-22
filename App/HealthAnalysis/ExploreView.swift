import HealthAnalysisCore
import SwiftUI

struct ExploreView: View {
    let application: HealthAnalysisApplication

    @State private var output: AnalysisSeriesID?
    @State private var inputIDs: Set<UUID> = []
    @State private var adjustmentIDs: Set<UUID> = []
    @State private var analysisTimeZone = TimeZone.current

    private var quantities: [TrackingQuantity] { application.analysisNumericQuantities }
    private var inputs: [TrackingQuantity] { quantities.filter { inputIDs.contains($0.id) } }
    private var adjustmentChoices: [TrackingQuantity] {
        application.analysisAdjustmentSuggestions(excluding: inputs.map(\.id))
    }
    private var adjustments: [TrackingQuantity] { adjustmentChoices.filter { adjustmentIDs.contains($0.id) } }

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
                    Text("Resting heart rate").tag(AnalysisSeriesID.health(metric: .restingHeartRate) as AnalysisSeriesID?)
                }
                .accessibilityIdentifier("explore.output")

                NavigationLink {
                    ExploreQuantitySelection(
                        title: "Inputs", quantities: quantities,
                        selection: Binding(
                            get: { inputIDs },
                            set: { selected in
                                inputIDs = selected
                                adjustmentIDs.subtract(selected)
                            }
                        )
                    )
                } label: {
                    LabeledContent("Inputs", value: selectionSummary(inputs))
                }
                .disabled(quantities.isEmpty)
                .accessibilityLabel("Inputs")
                .accessibilityValue(selectionSummary(inputs))
                .accessibilityIdentifier("explore.inputs")

                NavigationLink {
                    ExploreQuantitySelection(
                        title: "Account for", quantities: adjustmentChoices,
                        selection: $adjustmentIDs, showsSuggestions: true
                    )
                } label: {
                    LabeledContent("Account for", value: selectionSummary(adjustments))
                }
                .disabled(adjustmentChoices.isEmpty)
                .accessibilityLabel("Account for")
                .accessibilityValue(selectionSummary(adjustments))
                .accessibilityIdentifier("explore.adjustments")
                LabeledContent("Behavior window") { Text("Complete preceding day") }
                    .accessibilityIdentifier("explore.behaviorWindow")
                LabeledContent("History") { Text("Full usable history") }
                    .accessibilityIdentifier("explore.history")
            } footer: {
                if quantities.isEmpty {
                    Text("Add a daily quantity in Settings to choose an input.")
                }
            }

            Section {
                if let output, !inputs.isEmpty {
                    NavigationLink("Analyze") {
                        ExploreResultView(
                            application: application,
                            configuration: AnalysisConfiguration(
                                output: output, inputs: inputs.map { .manualQuantity($0.id) },
                                adjustmentInputs: adjustments.map { .manualQuantity($0.id) },
                                timeZone: analysisTimeZone
                            )
                        )
                    }
                } else {
                    Button("Analyze") {}
                        .disabled(true)
                }
            }
        }
    }

    private func selectionSummary(_ selected: [TrackingQuantity]) -> String {
        switch selected.count {
        case 0: String(localized: "None")
        case 1: selected[0].name
        default: String(localized: "\(selected.count) selected")
        }
    }
}

private struct ExploreQuantitySelection: View {
    let title: LocalizedStringKey
    let quantities: [TrackingQuantity]
    @Binding var selection: Set<UUID>
    var showsSuggestions = false

    var body: some View {
        Form {
            Section {
                ForEach(quantities) { quantity in
                    Toggle(
                        "\(quantity.name) (\(quantity.unit))",
                        isOn: Binding(
                            get: { selection.contains(quantity.id) },
                            set: { selected in
                                if selected { selection.insert(quantity.id) }
                                else { selection.remove(quantity.id) }
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
