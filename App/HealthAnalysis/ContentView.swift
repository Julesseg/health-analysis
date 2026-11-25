import HealthAnalysisCore
import SwiftUI

struct ContentView: View {
    @State private var session = HealthAnalysisSession()
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
                    VStack(alignment: .leading) {
                        WeekStrip(selection: $session.logDate)
                        List {
                            Section {
                                Text("No tracking variables configured.")
                            } header: {
                                Text(session.logDate, format: .dateTime.weekday(.wide).month(.wide).day().year())
                                    .accessibilityIdentifier("selectedLogDate")
                            }
                        }
                    }
                    .navigationTitle("Log")
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

private struct WeekStrip: View {
    @Binding var selection: Date
    @Environment(\.calendar) private var calendar
    @State private var week = 0
    @State private var oldestWeek = -4
    @ScaledMetric private var stripHeight: CGFloat = 60

    var body: some View {
        let today = calendar.startOfDay(for: .now)
        TabView(selection: $week) {
            ForEach(oldestWeek...0, id: \.self) { weekIndex in
                HStack(spacing: 0) {
                    ForEach(0..<7) { column in
                        let offset = weekIndex * 7 + column - 6
                        if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                            dayButton(day, offset: offset)
                        }
                    }
                }
                .tag(weekIndex)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: stripHeight)
        .padding(.horizontal)
        .onAppear { week = 0 }
        .onChange(of: week) {
            if week == oldestWeek { oldestWeek -= 4 }
        }
    }

    private func dayButton(_ day: Date, offset: Int) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selection)
        return Button {
            selection = day
        } label: {
            VStack {
                Text(day, format: .dateTime.weekday(.abbreviated))
                    .font(.caption)
                Text(day, format: .dateTime.day())
                    .font(.body.weight(selected ? .bold : .regular))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).month(.wide).day().year()))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("logDay-\(-offset)")
    }
}
