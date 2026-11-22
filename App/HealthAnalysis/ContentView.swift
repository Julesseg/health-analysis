import HealthAnalysisCore
import SwiftUI

struct ContentView: View {
    let application: HealthAnalysisApplication
    @AppStorage("disabledDiscoverySeries") private var storedDisabledSeries = Data()
    @Environment(\.timeZone) private var timeZone
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Destination = .insights
    @State private var presentedSheet: PresentedSheet?

    private enum Destination {
        case insights
        case explore
        case data
    }

    private enum PresentedSheet: String, Identifiable {
        case log
        case settings

        var id: Self { self }
    }

    private var overview: HealthAnalysisApplication.Overview { application.overview }

    private var disabledSeries: Binding<Set<AnalysisSeriesID>> {
        Binding {
            (try? JSONDecoder().decode(Set<AnalysisSeriesID>.self, from: storedDisabledSeries)) ?? []
        } set: { series in
            if let encoded = try? JSONEncoder().encode(series) { storedDisabledSeries = encoded }
        }
    }

    private struct InsightsRequest: Equatable {
        let historyVersion: Int
        let enabledSeries: Set<AnalysisSeriesID>
        let timeZone: TimeZone
        let followedIDs: [SavedAnalysis.ID]
        let isBackground: Bool
    }

    var body: some View {
        let request = InsightsRequest(
            historyVersion: application.healthMeasurements.reconciliationVersion,
            enabledSeries: Set(application.discoverySeries).subtracting(disabledSeries.wrappedValue),
            timeZone: timeZone, followedIDs: application.savedAnalyses.following.map(\.id),
            isBackground: scenePhase == .background
        )
        TabView(selection: $selectedTab) {
            Tab("Insights", systemImage: "lightbulb", value: Destination.insights) {
                destination("Insights") {
                    InsightsView(application: application, disabledSeries: disabledSeries) { selectedTab = .explore }
                }
            }
            Tab("Explore", systemImage: "magnifyingglass", value: Destination.explore) {
                destination("Explore") { ExploreView(application: application) }
            }
            Tab("Data", systemImage: "list.bullet", value: Destination.data) {
                destination("Data") { data }
            }
        }
        .task(id: request) {
            guard !request.isBackground else { return }
            await application.refreshReconciledHealthInsights(timeZone: request.timeZone, enabledSeries: request.enabledSeries)
        }
        .sheet(item: $presentedSheet) { sheet in
            NavigationStack {
                sheetContent(sheet)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") {
                                presentedSheet = nil
                            }
                        }
                    }
            }
        }
    }

    private func destination<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Log", systemImage: "square.and.pencil") {
                            presentedSheet = .log
                        }
                        Button("Settings", systemImage: "gearshape") {
                            presentedSheet = .settings
                        }
                    }
                }
        }
    }

    private var data: some View {
        List {
            HealthMeasurementsSection(history: application.healthMeasurements)
            ActivitySection(history: application.healthMeasurements)
            if !overview.hasTrackingVariables {
                Section("Daily log") {
                    Text("No tracking variables")
                }
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: PresentedSheet) -> some View {
        switch sheet {
        case .log:
            ManualLogView(log: application.manualLog)
        case .settings:
            ManualTrackingSettingsView(log: application.manualLog)
        }
    }
}
