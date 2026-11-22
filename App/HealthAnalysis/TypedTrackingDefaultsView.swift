import HealthAnalysisCore
import SwiftUI

struct TypedTrackingDefaultsView: View {
    let log: ManualLog
    let variable: TypedTrackingVariable
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        let versions = log.typedDefaults(variable.id)
        Form {
            Section("Default history") {
                ForEach(versions.reversed(), id: \.effectiveOn) { version in
                    if let date = date(for: version.effectiveOn) {
                        LabeledContent {
                            valueLabel(version.value)
                        } label: {
                            Text(date, style: .date)
                        }
                    }
                }
            }
            if let first = versions.first, let firstDate = date(for: first.effectiveOn) {
                Section {
                    let effectiveDate = max(.now, firstDate)
                    let day = ManualLogDay(effectiveDate, timeZone: timeZone)
                    NavigationLink("Change default") {
                        TypedDefaultEditor(
                            log: log, variable: variable, scope: .effectiveDate,
                            earliestDate: firstDate, effectiveDate: effectiveDate,
                            value: versions.last { $0.effectiveOn <= day }?.value ?? first.value
                        )
                    }
                    if let lastOlderDate = calendar.date(byAdding: .day, value: -1, to: firstDate) {
                        NavigationLink("Fill older history") {
                            TypedDefaultEditor(
                                log: log, variable: variable, scope: .olderHistory,
                                latestDate: lastOlderDate, effectiveDate: lastOlderDate, value: first.value
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: variable.name))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func valueLabel(_ value: ManualTrackingValue) -> some View {
        switch (variable.kind, value) {
        case (.count, .count(let number)), (.rating, .rating(let number)):
            Text(number, format: .number)
        case (.yesNo, .yesNo(let isOn)):
            Text(isOn ? LocalizedStringKey("Yes") : "No")
        case (.category(let options), .category(let id)):
            Text(verbatim: options.first { $0.id == id }?.name ?? "")
        default:
            Text("This tracking value is unavailable.")
        }
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

private struct TypedDefaultEditor: View {
    let log: ManualLog
    let variable: TypedTrackingVariable
    let scope: ManualDefaultScope
    var latestDate: Date?
    var earliestDate: Date?
    @State var effectiveDate: Date
    @State var value: ManualTrackingValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.timeZone) private var timeZone
    @State private var saveFailed = false

    var body: some View {
        Form {
            Section {
                TypedTrackingValueControl(variable: variable, label: Text("Default value"), value: $value)
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
                Button("Save", action: save)
            }
        }
    }

    private func save() {
        do {
            try log.setTypedDefault(
                variable.id, value: value, effectiveOn: ManualLogDay(effectiveDate, timeZone: timeZone), scope: scope
            )
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}
