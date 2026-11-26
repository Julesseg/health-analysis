import HealthAnalysisCore
import SwiftUI

struct ContentView: View {
    @Binding var session: HealthAnalysisSession
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: Binding(get: { session.tab }, set: { session.selectTab($0) })) {
            Tab("Analysis", systemImage: "chart.xyaxis.line", value: HealthAnalysisSession.Tab.analysis) {
                NavigationStack {
                    ContentUnavailableView {
                        Label("No saved analyses yet.", systemImage: "chart.xyaxis.line")
                    } actions: {
                        NavigationLink("Discover") {
                            ContentUnavailableView("Discovery is coming in a later build.", systemImage: "magnifyingglass")
                                .navigationTitle("Discover")
                        }
                        .buttonStyle(.bordered)
                    }
                    .navigationTitle("Analysis")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Settings", systemImage: "gearshape") { showingSettings = true }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                Form {
                                    LabeledContent("Inputs") { Text("None selected") }
                                    LabeledContent("Output") { Text("None selected") }
                                }
                                .navigationTitle("New Analysis")
                            } label: {
                                Label("New Analysis", systemImage: "plus")
                            }
                        }
                    }
                }
            }
            Tab("Log", systemImage: "calendar", value: HealthAnalysisSession.Tab.log) {
                NavigationStack {
                    LogView(session: $session)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                Form { LabeledContent("App") { Text("Health Analysis") } }
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
    }
}
