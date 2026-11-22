import HealthAnalysisCore
import SwiftUI

struct AnalysisPresetsView: View {
    let application: HealthAnalysisApplication
    let timeZone: TimeZone
    let onSelect: (AnalysisConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let presets = application.analysisPresets(timeZone: timeZone)
        List {
            Section {
                if presets.isEmpty {
                    Text("Suggested questions need a readable Health outcome and a supported tracking variable. Check Health coverage in Data or add a tracking variable in Settings.")
                }
                ForEach(presets, id: \.self) { preset in
                    if let input = preset.inputs.first {
                        let outputTitle = application.analysisSeriesTitle(preset.output)
                        let inputTitle = application.analysisSeriesTitle(input)
                        Button {
                            onSelect(preset)
                            dismiss()
                        } label: {
                            Text("\(outputTitle) with \(inputTitle)")
                        }
                    }
                }
            }
            Section("Heart rate variability") {
                Text(HRVSeries.AnalysisLimitation.unverifiedOriginalMeasureAndSummary.message)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Suggested questions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
