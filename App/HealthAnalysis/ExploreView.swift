import HealthAnalysisCore
import SwiftUI

struct ExploreView: View {
    let application: HealthAnalysisApplication

    @State private var output: AnalysisSeriesID?
    @State private var inputID: UUID?
    @State private var analysisTimeZone = TimeZone.current

    private var caffeine: TrackingQuantity? {
        application.analysisCaffeineQuantities.first { $0.id == inputID }
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
                    Text("Resting heart rate").tag(AnalysisSeriesID.health(metric: .restingHeartRate) as AnalysisSeriesID?)
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
                if let output, let caffeine {
                    NavigationLink("Analyze") {
                        ExploreResultView(
                            application: application,
                            configuration: AnalysisConfiguration(
                                output: output, inputs: [.manualQuantity(caffeine.id)], timeZone: analysisTimeZone
                            ),
                            inputName: caffeine.name
                        )
                    }
                } else {
                    Button("Analyze") {}
                        .disabled(true)
                }
            }
        }
    }
}
