import HealthAnalysisCore
import SwiftUI

struct SuggestedTrackingSection: View {
    let log: ManualLog
    @Environment(\.locale) private var locale

    var body: some View {
        let suggestions = log.suggestedTrackingVariables
        if !suggestions.isEmpty {
            Section("Suggested tracking variables") {
                ForEach(suggestions) { suggestion in
                    NavigationLink {
                        editor(for: suggestion)
                    } label: {
                        Text(suggestion.title)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editor(for suggestion: SuggestedTrackingVariable) -> some View {
        let name = String(localized: suggestion.title)
        switch suggestion.definition {
        case .quantity(let unit, let defaultValue):
            CreateTrackingQuantityView(
                log: log, suggestion: suggestion, name: name, unit: unit,
                defaultText: QuantityNumber.format(defaultValue, locale: locale)
            )
        case .count:
            CreateTypedTrackingVariableView(log: log, kind: .count, suggestion: suggestion, name: name)
        case .rating:
            CreateTypedTrackingVariableView(log: log, kind: .rating, suggestion: suggestion, name: name)
        }
    }
}

private extension SuggestedTrackingVariable {
    var title: LocalizedStringResource {
        switch self {
        case .caffeine: "Caffeine"
        case .alcohol: "Alcohol drinks"
        case .medicationIntake: "Medication doses"
        case .stress: "Stress"
        case .energy: "Energy"
        case .workoutDuration: "Workout duration"
        case .runningDuration: "Running duration"
        }
    }
}
