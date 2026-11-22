import HealthAnalysisCore
import SwiftUI

struct QuantityDefaultsView: View {
    let log: ManualLog
    let quantity: TrackingQuantity
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        let versions = log.quantityDefaults(quantity.id)
        Form {
            Section("Default history") {
                ForEach(versions.reversed(), id: \.effectiveOn) { version in
                    if let date = date(for: version.effectiveOn) {
                        LabeledContent {
                            Text("\(version.value, format: .number) \(quantity.unit)")
                        } label: {
                            Text(date, style: .date)
                        }
                    }
                }
            }

            if let first = versions.first, let firstDate = date(for: first.effectiveOn) {
                Section {
                    NavigationLink("Change default") {
                        QuantityDefaultEditor(
                            log: log, quantityID: quantity.id, scope: .effectiveDate,
                            earliestDate: firstDate, effectiveDate: max(.now, firstDate)
                        )
                    }
                    if let lastOlderDate = calendar.date(byAdding: .day, value: -1, to: firstDate) {
                        NavigationLink("Fill older history") {
                            QuantityDefaultEditor(
                                log: log, quantityID: quantity.id, scope: .olderHistory,
                                latestDate: lastOlderDate, effectiveDate: lastOlderDate
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: quantity.name))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(for day: ManualLogDay) -> Date? {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
    }
}

private struct QuantityDefaultEditor: View {
    let log: ManualLog
    let quantityID: TrackingQuantity.ID
    let scope: ManualDefaultScope
    var latestDate: Date?
    var earliestDate: Date?
    @State var effectiveDate: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @State private var valueText = ""
    @State private var saveFailed = false

    var body: some View {
        let value = QuantityNumber.parse(valueText, locale: locale)
        Form {
            Section {
                TextField("Default value", text: $valueText)
                    .keyboardType(.numbersAndPunctuation)
                if !valueText.isEmpty, value == nil {
                    Text("Enter a number.").foregroundStyle(.red).font(.footnote)
                }
            }

            Section {
                ManualLogDatePicker(
                    title: "Effective date", date: $effectiveDate,
                    latestDate: latestDate, earliestDate: earliestDate
                )
            } footer: {
                if scope == .olderHistory {
                    Text("Applies through the day before the first existing default.")
                }
            }

            if saveFailed {
                Section {
                    Text("Couldn’t save this default. Try again.").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(scope == .olderHistory ? LocalizedStringKey("Fill older history") : "Change default")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if let value { save(value) }
                }
                .disabled(value == nil)
            }
        }
    }

    private func save(_ value: Decimal) {
        do {
            try log.setQuantityDefault(
                quantityID, value: value, effectiveOn: ManualLogDay(effectiveDate, timeZone: timeZone), scope: scope
            )
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}
