import HealthAnalysisCore
import SwiftUI

struct LogVariableDefaultView: View {
    @Binding var session: HealthAnalysisSession
    let variable: LogVariable
    let selectedDay: LogDay
    let timeZone: TimeZone
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @State private var draft: LogDefaultDraft
    @State private var effectiveDate: Date
    @State private var appliesToEarlierDates = false
    @State private var error: LogVariableSettingsError?

    init(session: Binding<HealthAnalysisSession>, variable: LogVariable, selectedDay: LogDay, timeZone: TimeZone) {
        _session = session
        self.variable = variable
        self.selectedDay = selectedDay
        self.timeZone = TimeZone(identifier: timeZone.identifier) ?? timeZone
        let draft = if case .count(let count) = variable.latestDefaultValue {
            LogDefaultDraft(countText: session.wrappedValue.formatCount(count))
        } else {
            LogDefaultDraft(choice: variable.latestDefaultValue)
        }
        _draft = State(initialValue: draft)
        let today = LogDay(.now, timeZone: self.timeZone)
        _effectiveDate = State(initialValue: max(today, variable.startDay).date(in: self.timeZone))
    }

    var body: some View {
        let format = Date.FormatStyle(date: .abbreviated, locale: locale, calendar: calendar, timeZone: .gmt)

        Form {
            Section {
                LabeledContent("Latest default") { latestDefaultLabel }
                LabeledContent("Effective date") {
                    Text(variable.latestDefaultDay.date(in: .gmt), format: format)
                }
            }
            Section {
                LogDefaultInput(kind: variable.kind, draft: $draft)
                LogDefaultDateFields(date: $effectiveDate, appliesToEarlierDates: $appliesToEarlierDates,
                                     selectedDay: selectedDay, trackingStart: variable.startDay)
            } header: {
                Text("Change Default")
            } footer: {
                if let error {
                    Text(error.message(for: variable.kind)).foregroundStyle(.red)
                } else {
                    Text("This default applies from the chosen date until the next scheduled default. Saved values are kept.")
                }
            }
        }
        .environment(\.timeZone, timeZone)
        .navigationTitle(variable.name)
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

    private var latestDefaultLabel: Text {
        if case .count(let count) = variable.latestDefaultValue {
            return Text(verbatim: session.formatCount(count))
        }
        return variable.kind.choices.first { $0.value == variable.latestDefaultValue }?.label ?? Text("No default")
    }

    private func save() {
        do {
            try session.changeLogDefault(
                variable.id, to: draft.value(in: session),
                effectiveDay: LogDay(effectiveDate, timeZone: timeZone),
                applyToEarlierDays: appliesToEarlierDates, today: LogDay(.now, timeZone: timeZone)
            )
            dismiss()
        } catch let settingsError {
            error = settingsError
        }
    }
}

struct LogDefaultDateFields: View {
    @Binding var date: Date
    @Binding var appliesToEarlierDates: Bool
    let selectedDay: LogDay
    var trackingStart: LogDay?
    @Environment(\.calendar) private var systemCalendar
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        let today = calendar.startOfDay(for: .now)
        let earliest = trackingStart.map { calendar.startOfDay(for: $0.date(in: timeZone)) } ?? .distantPast
        let minimum = appliesToEarlierDates ? earliest : max(earliest, today)

        Toggle("Apply to Earlier Dates", isOn: $appliesToEarlierDates)
            .onChange(of: appliesToEarlierDates) {
                let selected = selectedDay.date(in: timeZone)
                if appliesToEarlierDates, selected < today {
                    date = max(selected, minimum)
                } else if date < minimum {
                    date = minimum
                }
            }
        DatePicker("Default starts", selection: $date, in: minimum..., displayedComponents: .date)
    }

    private var calendar: Calendar {
        var calendar = systemCalendar
        calendar.timeZone = timeZone
        return calendar
    }
}

struct LogDefaultDraft {
    var countText = ""
    var choice: LogValue?

    func value(in session: HealthAnalysisSession) throws(LogVariableSettingsError) -> LogValue? {
        guard !countText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return choice }
        guard let count = session.parseCount(countText) else { throw .invalidDefault }
        return .count(count)
    }
}

struct LogDefaultInput: View {
    let kind: LogVariable.Kind
    @Binding var draft: LogDefaultDraft

    var body: some View {
        if case .count = kind {
            TextField("Default value (optional)", text: $draft.countText)
                .keyboardType(.numberPad)
        } else {
            Picker("Default value", selection: $draft.choice) {
                Text("No default").tag(nil as LogValue?)
                ForEach(kind.choices) { choice in
                    choice.label.tag(Optional(choice.value))
                }
            }
            .menuOrder(.fixed)
            .accessibilityIdentifier("logVariableDefault")
        }
    }
}

extension LogVariableSettingsError {
    func message(for kind: LogVariable.Kind) -> LocalizedStringKey {
        switch self {
        case .missingName: "Enter a name."
        case .invalidOptions: "Enter at least two different option labels."
        case .invalidDefault:
            if case .count = kind { "Enter a nonnegative whole number." } else { "Choose one of the listed options." }
        case .defaultBeforeTracking: "Choose a date on or after the first day of tracking."
        case .earlierDefaultRequiresConfirmation: "Choose today or later, or turn on Apply to Earlier Dates."
        case .saveFailed: "Couldn’t save this tracking variable. Tap Save to retry."
        }
    }
}
