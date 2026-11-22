import HealthAnalysisCore
import SwiftUI

struct ContentView: View {
    let application: HealthAnalysisApplication
    @State private var presentedSheet: PresentedSheet?

    private enum PresentedSheet: String, Identifiable {
        case log
        case settings

        var id: Self { self }
    }

    private var overview: HealthAnalysisApplication.Overview { application.overview }

    var body: some View {
        TabView {
            Tab("Insights", systemImage: "lightbulb") {
                destination("Insights") { insights }
            }
            Tab("Explore", systemImage: "magnifyingglass") {
                destination("Explore") { ExploreView(application: application) }
            }
            Tab("Data", systemImage: "list.bullet") {
                destination("Data") { data }
            }
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

    private var insights: some View {
        List {
            if !overview.hasFollowedAnalyses {
                Section("Following") {
                    Text("No followed analyses yet")
                }
            }
            if !overview.hasDiscoveries {
                Section("Discovered for you") {
                    Text("No discoveries yet")
                }
            }
            LatestHealthMeasurementsSection(history: application.healthMeasurements)
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
