import HealthAnalysisCore
import SwiftUI

struct LogCategoriesView: View {
    @Binding var session: HealthAnalysisSession
    let selectedDay: LogDay
    @State private var newVariable: NewLogVariable?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.quantities) { quantity in
                    NavigationLink {
                        QuantitySetupView(session: $session, quantity: quantity, selectedDay: selectedDay, timeZone: timeZone)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(quantity.name) (\(quantity.unit))")
                            if let end = quantity.endDay {
                                let format = Date.FormatStyle(date: .abbreviated, locale: locale, calendar: calendar, timeZone: .gmt)
                                let today = LogDay(.now, timeZone: timeZone)
                                let date = end.date(in: .gmt)
                                Group {
                                    if end < today {
                                        Text("Archived · \(date, format: format)")
                                    } else {
                                        Text("Ends \(date, format: format)")
                                    }
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                ForEach(session.logVariables) { variable in
                    NavigationLink {
                        LogVariableDefaultView(
                            session: $session, variable: variable, selectedDay: selectedDay,
                            timeZone: timeZone
                        )
                    } label: {
                        LabeledContent {
                            Text(variable.kind.typeLabel)
                        } label: {
                            variable.label
                        }
                    }
                }
            }
            .overlay {
                if session.quantities.isEmpty && session.logVariables.isEmpty {
                    ContentUnavailableView("No tracking variables", systemImage: "list.bullet")
                }
            }
            .navigationTitle("Log Categories")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $newVariable) { type in
                if type == .quantity {
                    QuantitySetupView(session: $session, selectedDay: selectedDay, timeZone: timeZone)
                } else {
                    LogVariableSetupView(session: $session, type: type, selectedDay: selectedDay, timeZone: timeZone)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("Add Variable", systemImage: "plus") {
                        ForEach(NewLogVariable.allCases) { type in
                            Button(type.addTitle) { newVariable = type }
                        }
                    }
                    .menuOrder(.fixed)
                }
            }
        }
    }
}
