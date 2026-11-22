import HealthAnalysisCore
import SwiftUI

struct AnalysisResultScreen: View {
    let application: HealthAnalysisApplication
    private let draft: AnalysisConfiguration?
    private let editingID: SavedAnalysis.ID?

    @State private var savedID: SavedAnalysis.ID?
    @State private var draftState: AnalysisRefreshState
    @State private var saveFailed = false

    init(application: HealthAnalysisApplication, questionID: SavedAnalysis.ID) {
        self.application = application
        draft = nil
        editingID = nil
        _savedID = State(initialValue: questionID)
        _draftState = State(initialValue: AnalysisRefreshState())
    }

    init(
        application: HealthAnalysisApplication, configuration: AnalysisConfiguration,
        editing id: SavedAnalysis.ID? = nil, discovery: CompletedAnalysis? = nil
    ) {
        self.application = application
        draft = configuration
        editingID = id
        let prior = id.flatMap { application.savedAnalyses.state(for: $0).completed } ?? discovery
        _draftState = State(initialValue: AnalysisRefreshState(
            completed: prior?.result.configuration == configuration ? prior : nil
        ))
    }

    private var analyses: SavedAnalyses { application.savedAnalyses }
    private var question: SavedAnalysis? { savedID.flatMap { analyses.question(id: $0) } }
    private var state: AnalysisRefreshState {
        guard let savedID else { return draftState }
        let saved = analyses.state(for: savedID)
        if saved.failure == nil, !saved.isRefreshing, question?.configuration == draft,
           let failure = draftState.failure {
            return AnalysisRefreshState(completed: saved.completed, failure: failure)
        }
        return saved
    }

    var body: some View {
        List {
            if savedID != nil && question == nil {
                ContentUnavailableView("Saved analysis unavailable", systemImage: "bookmark")
            } else {
                if let completed = state.completed {
                    if discoveryBaseline?.discovery != nil {
                        Section {
                            Text("Selected in an exploratory search").font(.headline)
                        }
                    }
                    ExploreResultView(
                        application: application,
                        result: completed.result
                    ) {
                        refreshStatus
                        if let selection = discoveryBaseline?.discovery {
                            discoveryEvidence(selection, showingOriginal: completed.discovery != nil)
                        }
                    }
                } else {
                    refreshStatus
                }
            }
        }
        .navigationTitle("Analysis result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { saveAction }
        }
        .task {
            if state.completed == nil, state.failure == nil { await refresh() }
        }
    }

    private var discoveryBaseline: CompletedAnalysis? {
        if let savedID { return analyses.discoveryBaseline(for: savedID) }
        return draftState.completed
    }

    private func discoveryEvidence(_ selection: DiscoverySelection, showingOriginal: Bool) -> some View {
        Section("Discovery evidence") {
            if showingOriginal {
                Text("Low confidence. The search screened \(selection.familySize) comparisons and checked the result across separate parts of the history.")
                let format = FloatingPointFormatStyle<Double>.number
                    .notation(selection.adjustedPValue < 0.001 ? .scientific : .automatic)
                    .precision(.significantDigits(2...3))
                LabeledContent("Search-adjusted p-value") {
                    Text(selection.adjustedPValue, format: format)
                }
                Text("The model interval describes the fitted association. The search-adjusted p-value accounts for the screened comparisons.")
            }
            LabeledContent("Discovery cutoff") {
                Text(selection.cutoff, format: .dateTime.month().day().year().hour().minute())
            }
            Text("Subsequent-data support is unassessed.")
        }
    }

    private var refreshStatus: some View {
        Section {
            if let completed = state.completed {
                LabeledContent("Last successful analysis") {
                    Text(completed.updatedAt, format: .dateTime.month().day().year().hour().minute())
                }
            }
            if state.isRefreshing {
                let title: LocalizedStringKey = state.completed == nil ? "Analyzing…" : "Refreshing analysis…"
                ProgressView(title)
            }
            if let failure = state.failure {
                Text(failure.message)
                    .foregroundStyle(.secondary)
                if failure.showsHealthHistoryLink {
                    let output = question?.configuration.output ?? draft?.output
                    NavigationLink("Inspect Health measurements") {
                        HealthMeasurementHistoryView(
                            history: application.healthMeasurements,
                            presentation: output?.isSleepDuration == true ? .sleep : .restingHeartRate
                        )
                    }
                }
            }
            if !state.isRefreshing && (savedID != nil || draftState.completed?.discovery == nil) {
                let title: LocalizedStringKey = state.failure == nil ? "Refresh analysis" : "Retry analysis"
                Button(title) {
                    Task { await refresh() }
                }
            }
            if let question {
                NavigationLink("Edit analysis") {
                    ExploreView(application: application, editing: question)
                        .navigationTitle("Edit analysis")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            if question == nil, let baseline = discoveryBaseline, baseline.discovery != nil {
                NavigationLink("Edit analysis") {
                    ExploreView(application: application, discovery: baseline)
                        .navigationTitle("Edit analysis")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            if saveFailed {
                Text("Couldn’t save this analysis. Try again.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var saveAction: some View {
        if let question {
            let pinned = analyses.isPinned(question.id)
            let title: LocalizedStringKey = pinned ? "Unpin from Insights" : "Pin to Insights"
            Button(title, systemImage: pinned ? "pin.slash" : "pin") {
                do {
                    try analyses.setPinned(!pinned, for: question.id)
                    saveFailed = false
                } catch {
                    saveFailed = true
                }
            }
            .accessibilityIdentifier(pinned ? "analysis.unpin" : "analysis.pin")
        } else if let draft {
            let title: LocalizedStringKey = editingID == nil ? "Save analysis" : "Update saved analysis"
            Button(title, systemImage: "bookmark") {
                do {
                    let saved = try analyses.save(draft, updating: editingID, completed: draftState.completed)
                    saveFailed = false
                    savedID = saved.id
                } catch {
                    saveFailed = true
                }
            }
            .disabled(state.isRefreshing)
            .accessibilityIdentifier(editingID == nil ? "analysis.save" : "analysis.update")
        }
    }

    private func refresh() async {
        guard !state.isRefreshing else { return }
        if let savedID {
            draftState = AnalysisRefreshState()
            await application.refreshSavedAnalysis(savedID)
        } else if let draft {
            let previous = draftState
            draftState = AnalysisRefreshState(completed: previous.completed, isRefreshing: true)
            switch await application.refreshAnalysis(draft) {
            case .success(let completed):
                draftState = AnalysisRefreshState(completed: completed)
            case .failure(let failure):
                draftState = AnalysisRefreshState(completed: previous.completed, failure: .analysis(failure))
            case nil:
                draftState = previous
            }
        }
    }
}

private extension AnalysisRefreshFailure {
    var showsHealthHistoryLink: Bool {
        switch self {
        case .analysis(.healthHistoryUnavailable), .analysis(.healthHistoryLoading), .analysis(.chooseOutputSource): true
        default: false
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .persistence:
            "Couldn’t save the refreshed analysis. Try again."
        case .analysis(let failure):
            switch failure {
            case .unsupportedConfiguration: "This analysis configuration is unavailable."
            case .inputUnavailable: "A selected input is unavailable."
            case .outputUnavailable: "The selected output is unavailable."
            case .binaryWindowUnavailable: "Yes/no analyses use the complete preceding day."
            case .binaryInteractionUnavailable: "Interactions with yes/no variables are unavailable."
            case .countWindowUnavailable: "Count analyses use the complete preceding day."
            case .countInteractionUnavailable: "Interactions with counts are unavailable."
            case .ratingWindowUnavailable: "Rating analyses use the complete preceding day."
            case .ratingInteractionUnavailable: "Interactions with ratings are unavailable."
            case .manualLogUnavailable: "Couldn’t open the daily log."
            case .chooseOutputSource: "Choose a preferred source for this output in Health measurements."
            case .healthHistoryUnavailable(let failure): failure.message
            case .healthHistoryLoading: "Health measurements are still being checked. Try again when the check finishes."
            }
        }
    }
}
