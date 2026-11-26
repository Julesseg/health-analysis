import HealthAnalysisCore
import SwiftUI

struct LogCategoriesView: View {
    @Binding var session: HealthAnalysisSession
    let selectedDay: LogDay
    @Environment(\.dismiss) private var dismiss
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        NavigationStack {
            List(session.quantities) { quantity in
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
            .overlay {
                if session.quantities.isEmpty {
                    ContentUnavailableView("No tracking variables", systemImage: "list.bullet")
                }
            }
            .navigationTitle("Log Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        QuantitySetupView(session: $session, selectedDay: selectedDay, timeZone: timeZone)
                    } label: {
                        Label("Add Quantity", systemImage: "plus")
                    }
                }
            }
        }
    }
}
