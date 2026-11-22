import HealthAnalysisCore
import SwiftUI

struct ExploreTemporalControls: View {
    @Binding var behaviorWindow: AnalysisBehaviorWindow
    @Binding var history: AnalysisPeriod

    var body: some View {
        Picker("Behavior window", selection: $behaviorWindow) {
            ForEach(AnalysisBehaviorWindow.allCases, id: \.self) { window in
                Text(window.title).tag(window)
            }
        }
        .accessibilityIdentifier("explore.behaviorWindow")
        Picker("History", selection: $history) {
            ForEach(AnalysisPeriod.allCases, id: \.self) { period in
                Text(period.title).tag(period)
            }
        }
        .accessibilityIdentifier("explore.history")
    }
}

struct ExploreTemporalSummary: View {
    let configuration: AnalysisConfiguration

    var body: some View {
        LabeledContent("Behavior window") { Text(configuration.behaviorWindow.title) }
            .accessibilityIdentifier("explore.result.behaviorWindow")
        LabeledContent("History") { Text(configuration.history.title) }
            .accessibilityIdentifier("explore.result.history")
    }
}

private extension AnalysisBehaviorWindow {
    var title: LocalizedStringKey {
        switch self {
        case .precedingDay: "Complete preceding day"
        case .precedingWeek: "Complete preceding 7 days"
        case .precedingMonth: "Complete preceding 30 days"
        }
    }
}

private extension AnalysisPeriod {
    var title: LocalizedStringKey {
        switch self {
        case .fullHistory: "Full usable history"
        case .last90Days: "Last 90 days"
        case .last365Days: "Last 365 days"
        }
    }
}
