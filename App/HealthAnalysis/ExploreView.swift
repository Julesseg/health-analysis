import HealthAnalysisCore
import SwiftUI

struct ExploreView: View {
    let application: HealthAnalysisApplication
    private let editing: SavedAnalysis?

    @State private var output: AnalysisSeriesID?
    @State private var inputID: UUID?
    @State private var analysisTimeZone = TimeZone.current

    init(application: HealthAnalysisApplication, editing: SavedAnalysis? = nil) {
        self.application = application
        self.editing = editing
        _output = State(initialValue: editing?.configuration.output)
        if case .manualQuantity(let id) = editing?.configuration.inputs.first {
            _inputID = State(initialValue: id)
        }
        _analysisTimeZone = State(initialValue: editing?.configuration.timeZone ?? .current)
    }

    private var caffeine: TrackingQuantity? {
        application.analysisCaffeineQuantities.first { $0.id == inputID }
    }

    private var configuration: AnalysisConfiguration? {
        guard let output, let caffeine else { return nil }
        let input = AnalysisSeriesID.manualQuantity(caffeine.id)
        var configuration = editing?.configuration ?? .init(output: output, inputs: [input], timeZone: analysisTimeZone)
        configuration.output = output
        if configuration.inputs.isEmpty {
            configuration.inputs = [input]
        } else {
            configuration.inputs[0] = input
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
                Picker("Output", selection: $output) {
                    Text("Choose output").tag(nil as AnalysisSeriesID?)
                    let restingHeartRate = AnalysisSeriesID.health(metric: .restingHeartRate)
                    Text("Resting heart rate").tag(restingHeartRate as AnalysisSeriesID?)
                    if let savedOutput = editing?.configuration.output, savedOutput != restingHeartRate {
                        application.analysisSeriesTitle(savedOutput).tag(savedOutput as AnalysisSeriesID?)
                    }
                }
                .accessibilityIdentifier("explore.output")

                Picker("Inputs", selection: $inputID) {
                    Text("Choose caffeine quantity").tag(nil as UUID?)
                    ForEach(application.analysisCaffeineQuantities) { quantity in
                        Text("\(quantity.name) (\(quantity.unit))").tag(quantity.id as UUID?)
                    }
                }
                .disabled(application.analysisCaffeineQuantities.isEmpty)
                .accessibilityIdentifier("explore.inputs")

                LabeledContent("Account for") { Text("Unavailable") }
                    .accessibilityIdentifier("explore.adjustments")
                LabeledContent("Behavior window") { Text("Complete preceding day") }
                    .accessibilityIdentifier("explore.behaviorWindow")
                LabeledContent("History") { Text("Full usable history") }
                    .accessibilityIdentifier("explore.history")
            } footer: {
                if application.analysisCaffeineQuantities.isEmpty {
                    Text("Add a daily caffeine quantity in milligrams (mg) in Settings.")
                } else {
                    Text("Choose the daily quantity you use to log caffeine in milligrams (mg).")
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
}
