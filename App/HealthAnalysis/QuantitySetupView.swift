import HealthAnalysisCore
import SwiftUI

struct QuantitySetupView: View {
    private enum Confirmation {
        case removeQuantity
        case removeEntries(count: Int, endDay: LogDay)
    }

    @Binding var session: HealthAnalysisSession
    private let quantity: LogQuantity?
    @Environment(\.dismiss) private var dismiss
    @State private var timeZone: TimeZone
    @State private var name: String
    @State private var unit: String
    @State private var defaultText: String
    @State private var startDate: Date
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var changesDefault = false
    @State private var defaultDate = Date.now
    @State private var error: QuantitySettingsError?
    @State private var removalFailed = false
    @State private var confirmation: Confirmation?

    init(session: Binding<HealthAnalysisSession>, quantity: LogQuantity? = nil, selectedDay: LogDay, timeZone: TimeZone) {
        _session = session
        self.quantity = quantity
        let timeZone = TimeZone(identifier: timeZone.identifier) ?? timeZone
        _timeZone = State(initialValue: timeZone)
        _name = State(initialValue: quantity?.name ?? "")
        _unit = State(initialValue: quantity?.unit ?? "")
        _defaultText = State(initialValue: quantity.map { session.wrappedValue.latestDefaultText(for: $0) } ?? "")
        let start = quantity?.startDay ?? selectedDay
        _startDate = State(initialValue: start.date(in: timeZone))
        _hasEnd = State(initialValue: quantity?.endDay != nil)
        _endDate = State(initialValue: (quantity?.endDay ?? max(start, selectedDay)).date(in: timeZone))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("quantityName")
                TextField("Unit", text: $unit)
                    .accessibilityIdentifier("quantityUnit")
                if quantity == nil { defaultField }
                DatePicker("Tracking starts", selection: $startDate, displayedComponents: .date)
                if quantity != nil {
                    Toggle("Set End Date", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Last logging day", selection: $endDate, displayedComponents: .date)
                    }
                }
            } footer: {
                if let error {
                    Text(message(for: error)).foregroundStyle(.red)
                } else if let quantity, unit != quantity.unit {
                    Text("Changing the unit relabels existing entries. Their numeric values stay the same.")
                }
            }
            if let quantity {
                Section {
                    LabeledContent("Latest default", value: session.latestDefaultText(for: quantity))
                    Toggle("Change Default", isOn: $changesDefault)
                    if changesDefault {
                        defaultField
                        DatePicker("Default starts", selection: $defaultDate, displayedComponents: .date)
                    }
                }
                Section {
                    Button("Remove Quantity", role: .destructive) { confirmation = .removeQuantity }
                } footer: {
                    if removalFailed {
                        Text("Couldn’t remove this quantity. Tap Remove Quantity to retry.")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .environment(\.timeZone, timeZone)
        .navigationTitle(quantity == nil ? "New Quantity" : "Edit Quantity")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .alert(confirmationTitle, isPresented: showsConfirmation, presenting: confirmation) { action in
            Button("Cancel", role: .cancel) {}
            switch action {
            case .removeQuantity:
                Button("Remove", role: .destructive) { removeQuantity() }
            case .removeEntries(_, let endDay):
                Button("Remove Entries and Save", role: .destructive) { save(confirmedEndDay: endDay) }
            }
        } message: { action in
            switch action {
            case .removeQuantity:
                Text("This permanently deletes the quantity and all its recorded entries.")
            case .removeEntries(1, _):
                Text("1 recorded entry falls after the new end date and will be permanently removed.")
            case .removeEntries(let count, _):
                Text("\(count) recorded entries fall after the new end date and will be permanently removed.")
            }
        }
    }

    private var showsConfirmation: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var confirmationTitle: LocalizedStringKey {
        if case .removeQuantity = confirmation, let quantity { return "Remove \(quantity.name)?" }
        return "Remove entries after the end date?"
    }

    private var defaultField: some View {
        TextField("Default value", text: $defaultText)
            .keyboardType(.numbersAndPunctuation)
    }

    private func save(confirmedEndDay: LogDay? = nil) {
        let start = LogDay(startDate, timeZone: timeZone)
        let end = confirmedEndDay ?? (hasEnd ? LogDay(endDate, timeZone: timeZone) : nil)
        do {
            if let quantity {
                try session.updateQuantity(
                    quantity.id, name: name, unit: unit, startDay: start,
                    endDay: end,
                    defaultChange: changesDefault ? (defaultText, LogDay(defaultDate, timeZone: timeZone)) : nil,
                    removeEntriesAfterEnd: confirmedEndDay != nil
                )
            } else {
                try session.createQuantity(name: name, unit: unit, defaultText: defaultText, effectiveDay: start)
            }
            dismiss()
        } catch let settingsError {
            if case .endDateWouldRemoveEntries(let count) = settingsError, let end {
                error = nil
                confirmation = .removeEntries(count: count, endDay: end)
            } else {
                error = settingsError
            }
        }
    }

    private func removeQuantity() {
        guard let quantity else { return }
        do {
            try session.removeQuantity(quantity.id)
            dismiss()
        } catch {
            removalFailed = true
        }
    }

    private func message(for error: QuantitySettingsError) -> LocalizedStringKey {
        switch error {
        case .missingName: "Enter a name."
        case .missingUnit: "Enter a unit."
        case .invalidDefault: "Enter a valid default value."
        case .invalidTrackingPeriod: "Choose an end date on or after the start date."
        case .rangeExcludesEntries: "Choose a start date on or before the first recorded entry."
        case .endDateWouldRemoveEntries: "The new end date excludes recorded entries."
        case .saveFailed: "Couldn’t save this quantity. Tap Save to retry."
        }
    }
}
