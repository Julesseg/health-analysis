import HealthAnalysisCore
import SwiftUI

struct QuantitySetupView: View {
    @Binding var session: HealthAnalysisSession
    @State var effectiveDate: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.timeZone) private var timeZone
    @State private var name = ""
    @State private var unit = ""
    @State private var defaultText = ""
    @State private var error: QuantityCreationError?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Unit", text: $unit)
                    TextField("Default value", text: $defaultText)
                        .keyboardType(.numbersAndPunctuation)
                    DatePicker("Default starts", selection: $effectiveDate, displayedComponents: .date)
                } footer: {
                    if let error {
                        Text(message(for: error))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Quantity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
    }

    private func save() {
        do {
            try session.createQuantity(
                name: name,
                unit: unit,
                defaultText: defaultText,
                effectiveDay: LogDay(effectiveDate, timeZone: timeZone)
            )
            dismiss()
        } catch let creationError {
            error = creationError
        }
    }

    private func message(for error: QuantityCreationError) -> LocalizedStringKey {
        switch error {
        case .missingName: "Enter a name."
        case .missingUnit: "Enter a unit."
        case .invalidDefault: "Enter a valid default value."
        case .saveFailed: "Couldn’t save this quantity. Tap Save to retry."
        }
    }
}
