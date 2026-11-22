import HealthAnalysisCore
import SwiftUI

struct DailyTypedEntryField: View {
    let log: ManualLog
    let row: DailyTypedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TypedTrackingValueControl(
                variable: row.variable,
                label: Text(verbatim: row.variable.name),
                value: Binding(
                    get: { log.dailyTypedEntry(row.id, on: row.day)?.displayedValue ?? row.displayedValue },
                    set: { log.editTypedEntry(row.id, on: row.day, value: $0) }
                )
            )
            feedback
        }
    }

    @ViewBuilder
    private var feedback: some View {
        switch row.status {
        case .assumedDefault:
            Text("Assumed default").foregroundStyle(.secondary).font(.footnote)
        case .saved:
            Text("Saved").foregroundStyle(.secondary).font(.footnote)
        case .invalid:
            Text("Choose a valid value.").foregroundStyle(.red).font(.footnote)
        case .saveFailed:
            Text("Couldn’t save this value.").foregroundStyle(.red).font(.footnote)
            Button("Retry save") {
                log.retryTypedEntry(row.id, on: row.day)
            }
            .accessibilityLabel(Text("Retry saving \(row.variable.name)"))
            .buttonStyle(.borderless)
        }
    }
}

struct TypedTrackingValueControl: View {
    let variable: TypedTrackingVariable
    let label: Text
    @Binding var value: ManualTrackingValue
    @Environment(\.locale) private var locale

    @ViewBuilder
    var body: some View {
        switch (variable.kind, value) {
        case (.count, .count(let count)):
            stepper(value: count, range: 0...Int.max, trackingValue: ManualTrackingValue.count)
        case (.yesNo, .yesNo(let isOn)):
            Toggle(isOn: Binding(get: { isOn }, set: { value = .yesNo($0) })) {
                label
            }
        case (.rating(let bounds), .rating(let rating)):
            stepper(value: rating, range: bounds, trackingValue: ManualTrackingValue.rating)
        case (.category(let options), .category(let selection)):
            Picker(selection: Binding(get: { selection }, set: { value = .category($0) })) {
                ForEach(options) { option in
                    Text(verbatim: option.name).tag(option.id)
                }
            } label: {
                label
            }
            .pickerStyle(.menu)
            .accessibilityLabel(label)
            .accessibilityValue(Text(verbatim: options.first { $0.id == selection }?.name ?? ""))
        default:
            Text("This tracking value is unavailable.")
        }
    }

    private func stepper(
        value number: Int, range: ClosedRange<Int>, trackingValue: @escaping (Int) -> ManualTrackingValue
    ) -> some View {
        let formatted = number.formatted(.number.locale(locale))
        let selection = Binding<Int>(
            get: {
                switch value {
                case .count(let current), .rating(let current): current
                default: number
                }
            },
            set: { value = trackingValue($0) }
        )
        return Stepper(value: selection, in: range) {
            VStack(alignment: .leading) {
                label
                Text(verbatim: formatted).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: formatted))
    }
}
