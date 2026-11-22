import HealthAnalysisCore
import SwiftUI

struct DailyTypedEntryField: View {
    let log: ManualLog
    let row: DailyTypedEntry
    @Environment(\.locale) private var locale

    private var name: Text { Text(verbatim: row.variable.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            control
            feedback
        }
    }

    @ViewBuilder
    private var control: some View {
        switch (row.variable.kind, row.displayedValue) {
        case (.count, .count(let count)):
            stepper(value: count, range: 0...Int.max, trackingValue: ManualTrackingValue.count)
        case (.yesNo, .yesNo(let isOn)):
            Toggle(isOn: Binding(get: { isOn }, set: { save(.yesNo($0)) })) {
                name
            }
        case (.rating(let bounds), .rating(let rating)):
            stepper(value: rating, range: bounds, trackingValue: ManualTrackingValue.rating)
        case (.category(let options), .category(let selection)):
            Picker(selection: Binding(get: { selection }, set: { save(.category($0)) })) {
                ForEach(options) { option in
                    Text(verbatim: option.name).tag(option.id)
                }
            } label: {
                name
            }
            .pickerStyle(.menu)
            .accessibilityLabel(name)
            .accessibilityValue(Text(verbatim: options.first { $0.id == selection }?.name ?? ""))
        default:
            Text("This tracking value is unavailable.")
        }
    }

    private func stepper(
        value: Int, range: ClosedRange<Int>, trackingValue: @escaping (Int) -> ManualTrackingValue
    ) -> some View {
        let formatted = value.formatted(.number.locale(locale))
        let selection = Binding<Int>(
            get: {
                switch log.dailyTypedEntry(row.id, on: row.day)?.displayedValue {
                case .count(let current), .rating(let current): current
                default: value
                }
            },
            set: { save(trackingValue($0)) }
        )
        return Stepper(value: selection, in: range) {
            VStack(alignment: .leading) {
                name
                Text(verbatim: formatted).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(name)
        .accessibilityValue(Text(verbatim: formatted))
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

    private func save(_ value: ManualTrackingValue) {
        log.editTypedEntry(row.id, on: row.day, value: value)
    }
}
