import HealthAnalysisCore
import SwiftUI

struct RatingSupportSections: View {
    let result: AnalysisResult

    var body: some View {
        if let output = result.outputVariable, let threshold = output.kind.ratingThreshold {
            Section {
                let recorded = result.observations.compactMap { observation in
                    observation.outputOrigin == .observation ? observation.outputTrackingValue : nil
                }
                support(recorded, threshold: threshold)
            } header: {
                Text("Output · \(output.analysisChoiceLabel)")
            }
        }
        ForEach(result.modeledInputs) { input in
            if let threshold = input.kind?.ratingThreshold {
                Section {
                    let recorded = result.inputEvidence(for: input.series).pairs.compactMap { pair in
                        pair.input.origin == .observation ? pair.input.trackingValue : nil
                    }
                    support(recorded, threshold: threshold)
                } header: {
                    Text(input.role == .input ? "Input · \(input.choiceLabel)" : "Account for · \(input.choiceLabel)")
                }
            }
        }
    }

    private func support(_ recorded: [ManualTrackingValue], threshold: Int) -> some View {
        let levels = recorded.compactMap { value -> Int? in
            if case .rating(let level) = value { return level }
            return nil
        }
        let below = levels.count { $0 < threshold }
        return Group {
            LabeledContent("Recorded below \(threshold, format: .number)") {
                Text(below, format: .number)
            }
            LabeledContent("Recorded at \(threshold, format: .number) or above") {
                Text(levels.count - below, format: .number)
            }
        }
    }
}
