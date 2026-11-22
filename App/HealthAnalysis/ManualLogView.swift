import HealthAnalysisCore
import SwiftUI

struct ManualLogView: View {
    let log: ManualLog
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @State private var date = Date.now
    @FocusState private var focusedQuantity: TrackingQuantity.ID?

    var body: some View {
        Group {
            if !log.isStoreAvailable {
                ContentUnavailableView("Couldn’t open the daily log", systemImage: "exclamationmark.circle")
            } else if log.quantities.isEmpty && log.typedVariables.isEmpty {
                ContentUnavailableView("No tracking variables", systemImage: "square.and.pencil")
            } else {
                dailyForm(on: ManualLogDay(date, timeZone: timeZone))
            }
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dailyForm(on day: ManualLogDay) -> some View {
        let rows = log.dailyQuantities(on: day, locale: locale)
        let typedRows = log.dailyTypedEntries(on: day)
        return Form {
            Section {
                ManualLogDatePicker(title: "Date", date: $date, latestDate: .now)
            }
            Section {
                if rows.isEmpty && typedRows.isEmpty {
                    Text("No tracking variables for this date")
                }
                Group {
                    ForEach(rows) { row in
                        quantityField(row, on: day)
                    }
                    ForEach(typedRows) { row in
                        DailyTypedEntryField(log: log, row: row)
                    }
                }
                .id(day)
            }
        }
        .onChange(of: date) { focusedQuantity = nil }
    }

    private func quantityField(_ row: DailyQuantity, on day: ManualLogDay) -> some View {
        let name = Text("\(row.quantity.name) (\(row.quantity.unit))")
        let text = Binding(
            get: { log.dailyQuantity(row.id, on: day, locale: locale)?.text ?? row.text },
            set: { log.editQuantity(row.id, on: day, text: $0, locale: locale) }
        )

        return VStack(alignment: .leading, spacing: 4) {
            name.accessibilityHidden(true)
            TextField("Value", text: text)
                .accessibilityLabel(name)
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(.done)
                .focused($focusedQuantity, equals: row.id)
                .onSubmit { focusedQuantity = nil }
            feedback(for: row, on: day)
        }
    }

    @ViewBuilder
    private func feedback(for row: DailyQuantity, on day: ManualLogDay) -> some View {
        switch row.status {
        case .assumedDefault:
            Text("Assumed default").foregroundStyle(.secondary).font(.footnote)
        case .saved:
            Text("Saved").foregroundStyle(.secondary).font(.footnote)
        case .invalid:
            Text("Enter a number.").foregroundStyle(.red).font(.footnote)
        case .saveFailed:
            Text("Couldn’t save this value.").foregroundStyle(.red).font(.footnote)
            Button("Retry save") {
                log.retryQuantity(row.id, on: day)
            }
            .accessibilityLabel(Text("Retry saving \(row.quantity.name)"))
            .buttonStyle(.borderless)
        }
    }
}
