import HealthAnalysisCore
import SwiftUI

struct ManualLogView: View {
    let log: ManualLog
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @State private var selectedDay: ManualLogDay?
    @FocusState private var focusedQuantity: TrackingQuantity.ID?

    var body: some View {
        let today = ManualLogDay(.now, timeZone: timeZone)
        Group {
            if !log.isStoreAvailable {
                ContentUnavailableView("Couldn’t open the daily log", systemImage: "exclamationmark.circle")
            } else if log.quantities.isEmpty && log.typedVariables.isEmpty {
                ContentUnavailableView("No tracking variables", systemImage: "square.and.pencil")
            } else {
                dailyForm(on: selectedDay ?? today, today: today)
            }
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedDay == nil { selectedDay = today }
        }
    }

    private func dailyForm(on day: ManualLogDay, today: ManualLogDay) -> some View {
        let rows = log.dailyQuantities(on: day, locale: locale)
        let typedRows = log.dailyTypedEntries(on: day)
        return Form {
            Section {
                dayPicker(on: day, today: today)
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
            if !rows.isEmpty || !typedRows.isEmpty {
                ManualLogReviewSection(log: log, day: day)
            }
        }
        .onChange(of: day) { focusedQuantity = nil }
    }

    private func dayPicker(on day: ManualLogDay, today: ManualLogDay) -> some View {
        var pickerCalendar = calendar
        pickerCalendar.timeZone = .gmt
        return ManualLogDatePicker(
            title: "Date",
            date: Binding(
                get: { pickerDate(for: selectedDay ?? day) },
                set: { selectedDay = ManualLogDay($0, timeZone: .gmt) }
            ),
            latestDate: pickerDate(for: max(today, day))
        )
        .environment(\.calendar, pickerCalendar)
        .environment(\.timeZone, .gmt)
    }

    private func pickerDate(for day: ManualLogDay) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: .gmt,
            year: day.year, month: day.month, day: day.day
        ).date!
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
