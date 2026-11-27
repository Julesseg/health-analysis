import HealthAnalysisCore
import SwiftUI

enum NewLogVariable: CaseIterable, Identifiable {
    case quantity, count, yesNo, rating, category

    var id: Self { self }

    var addTitle: LocalizedStringKey {
        switch self {
        case .quantity: "Add Quantity"
        case .count: "Add Count"
        case .yesNo: "Add Yes/No"
        case .rating: "Add Rating"
        case .category: "Add Category"
        }
    }

    var navigationTitle: LocalizedStringKey {
        switch self {
        case .quantity: "New Quantity"
        case .count: "New Count"
        case .yesNo: "New Yes/No Field"
        case .rating: "New Rating"
        case .category: "New Category"
        }
    }
}

struct LogVariableSetupView: View {
    @Binding var session: HealthAnalysisSession
    let type: NewLogVariable
    let timeZone: TimeZone
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = ""
    @State private var options = [LogOption(label: ""), LogOption(label: "")]
    @State private var defaultDraft = LogDefaultDraft()
    @State private var startDate: Date
    @State private var error: LogVariableSettingsError?

    init(session: Binding<HealthAnalysisSession>, type: NewLogVariable, selectedDay: LogDay, timeZone: TimeZone) {
        _session = session
        self.type = type
        self.timeZone = TimeZone(identifier: timeZone.identifier) ?? timeZone
        _startDate = State(initialValue: selectedDay.date(in: self.timeZone))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("logVariableName")
                if type == .count {
                    TextField("Unit (optional)", text: $unit)
                }
                DatePicker("Tracking starts", selection: $startDate, displayedComponents: .date)
            } footer: {
                if let error {
                    Text(error.message(for: kind)).foregroundStyle(.red)
                }
            }
            if type == .rating || type == .category {
                optionSettings
            }
            Section {
                LogDefaultInput(kind: kind, draft: $defaultDraft)
            } footer: {
                Text("The default starts on the first day of tracking.")
            }
        }
        .environment(\.timeZone, timeZone)
        .navigationTitle(type.navigationTitle)
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
    }

    private var optionSettings: some View {
        Section {
            ForEach($options) { $option in
                let position = (options.firstIndex { $0.id == option.id } ?? 0) + 1
                TextField("Option \(position)", text: $option.label)
            }
            .onDelete { offsets in
                if offsets.contains(where: { .option(options[$0].id) == defaultDraft.choice }) {
                    defaultDraft.choice = nil
                }
                options.remove(atOffsets: offsets)
            }
            Button("Add Option", systemImage: "plus") { options.append(LogOption(label: "")) }
        } header: {
            Text("Options")
        } footer: {
            if type == .rating {
                Text("Enter ratings from lowest to highest.")
            }
        }
    }

    private var kind: LogVariable.Kind {
        switch type {
        case .count: .count(unit: unit)
        case .yesNo: .yesNo
        case .rating: .rating(options)
        case .category: .category(options)
        case .quantity: preconditionFailure("Use QuantitySetupView for quantities")
        }
    }

    private func save() {
        do {
            try session.createLogVariable(
                name: name, kind: kind, defaultValue: defaultDraft.value(in: session),
                startDay: LogDay(startDate, timeZone: timeZone)
            )
            dismiss()
        } catch let settingsError {
            error = settingsError
        }
    }
}

struct LogChoice: Identifiable {
    let value: LogValue
    let label: Text
    var id: LogValue { value }
}

extension LogVariable.Kind {
    var choices: [LogChoice] {
        switch self {
        case .count:
            []
        case .yesNo:
            [LogChoice(value: .yesNo(true), label: Text("Yes")), LogChoice(value: .yesNo(false), label: Text("No"))]
        case .rating, .category:
            options.filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { LogChoice(value: .option($0.id), label: Text(verbatim: $0.label)) }
        }
    }

    var typeLabel: LocalizedStringKey {
        switch self {
        case .count: "Count"
        case .yesNo: "Yes/No"
        case .rating: "Rating"
        case .category: "Category"
        }
    }
}

extension LogVariable {
    var label: Text {
        if case .count(let unit?) = kind {
            Text("\(name) (\(unit))")
        } else {
            Text(verbatim: name)
        }
    }
}
