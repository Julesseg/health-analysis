import HealthAnalysisCore
import SwiftUI

struct ManualTrackingSettingsView: View {
    let log: ManualLog

    var body: some View {
        Form {
            Section("Tracking variables") {
                if log.isStoreAvailable {
                    ForEach(log.quantities) { quantity in
                        NavigationLink {
                            QuantityDefaultsView(log: log, quantity: quantity)
                        } label: {
                            LabeledContent {
                                Text(verbatim: quantity.unit)
                            } label: {
                                Text(verbatim: quantity.name)
                            }
                        }
                        .accessibilityLabel(Text(verbatim: quantity.name))
                        .accessibilityValue(Text(verbatim: quantity.unit))
                    }
                    NavigationLink("Add quantity") {
                        CreateTrackingQuantityView(log: log)
                    }
                    TypedTrackingSettings(log: log)
                } else {
                    Text("Couldn’t open the daily log")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CreateTrackingQuantityView: View {
    let log: ManualLog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @State private var name = ""
    @State private var unit = ""
    @State private var defaultText = ""
    @State private var startDate = Date.now
    @State private var didFailToSave = false

    var body: some View {
        let defaultValue = QuantityNumber.parse(defaultText, locale: locale)
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Unit", text: $unit)
                TextField("Default value", text: $defaultText)
                    .keyboardType(.numbersAndPunctuation)
                if !defaultText.isEmpty, defaultValue == nil {
                    Text("Enter a number.").foregroundStyle(.red).font(.footnote)
                }
            }
            Section {
                ManualLogDatePicker(title: "Start date", date: $startDate)
            }
            if didFailToSave {
                Section {
                    Text("Couldn’t add this quantity. Try again.").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("New quantity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    if let defaultValue { addQuantity(defaultValue: defaultValue) }
                }
                .disabled(
                    defaultValue == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }

    private func addQuantity(defaultValue: Decimal) {
        do {
            try log.createQuantity(
                name: name,
                unit: unit,
                defaultValue: defaultValue,
                startsOn: ManualLogDay(startDate, timeZone: timeZone)
            )
            dismiss()
        } catch {
            didFailToSave = true
        }
    }
}
