import HealthAnalysisCore
import SwiftUI

struct ContentView: View {
    @State private var session = HealthAnalysisSession()

    var body: some View {
        TabView(selection: $session.tab) {
            Tab("Insights", systemImage: "lightbulb", value: .insights) {
                page("Insights") {
                    List {
                        Section("Following") {
                            quantity(session.library.savedAnalyses, empty: "No saved analyses yet.")
                        }
                        Section("Discovered for you") {
                            quantity(session.library.discoveries, empty: "No patterns to show yet.")
                        }
                        Section("Latest measurements") {
                            quantity(session.library.measurements, empty: "No measurements available.")
                        }
                    }
                }
            }
            Tab("Explore", systemImage: "magnifyingglass", value: .explore) {
                page("Explore") {
                    if !session.library.canExplore {
                        ContentUnavailableView(
                            "No variables to explore", systemImage: "magnifyingglass",
                            description: Text("Analyses use measurements and daily log entries.")
                        )
                    }
                }
            }
            Tab("Data", systemImage: "list.bullet", value: .data) {
                page("Data") {
                    List {
                        Section("Apple Health") {
                            quantity(session.library.measurements, empty: "No measurements available.")
                        }
                        Section("Daily log") {
                            quantity(session.library.trackingVariables, empty: "No tracking variables configured.")
                        }
                    }
                }
            }
        }
        .sheet(item: $session.sheet) { sheet in
            NavigationStack {
                Group {
                    switch sheet {
                    case .log:
                        Form {
                            DatePicker("Day", selection: $session.logDate, in: ...Date.now, displayedComponents: .date)
                            Section("Daily log") {
                                quantity(session.library.trackingVariables, empty: "No tracking variables configured.")
                            }
                        }
                        .navigationTitle("Log")
                    case .settings:
                        Form {
                            LabeledContent("App") { Text("Health Analysis") }
                        }
                        .navigationTitle("Settings")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { session.sheet = nil }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quantity(_ count: Int, empty: LocalizedStringKey) -> some View {
        if count == 0 {
            Text(empty)
        } else {
            Text(count, format: .number)
        }
    }

    private func page<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape") { session.sheet = .settings }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Log", systemImage: "square.and.pencil") { session.openLog() }
                    }
                }
        }
    }
}
