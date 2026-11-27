import HealthAnalysisCore
import SwiftUI

struct LogView: View {
    @Binding var session: HealthAnalysisSession
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var showingCategories = false
    @FocusState private var focusedVariable: UUID?

    var body: some View {
        Group {
            if session.isLogAvailable {
                dailyLog
            } else {
                ContentUnavailableView {
                    Label("Couldn’t open the daily log", systemImage: "exclamationmark.circle")
                } actions: {
                    Button("Retry") { session.retryOpeningLog() }
                }
            }
        }
        .navigationTitle("Log")
    }

    private var dailyLog: some View {
        let day = session.logDay
        let quantities = session.logFields(on: day)
        let variables = session.typedLogFields(on: day)
        let hasFields = !quantities.isEmpty || !variables.isEmpty

        return VStack(alignment: .leading) {
            WeekStrip(
                selection: day,
                status: { session.logStatus(on: $0) },
                select: { session.selectLogDay($0) }
            )
            Form {
                Section {
                    if !hasFields {
                        if session.quantities.isEmpty && session.logVariables.isEmpty {
                            Text("No tracking variables configured.")
                        } else {
                            Text("No tracking variables for this day.")
                        }
                    }
                    ForEach(quantities) { field in
                        LogNumberRow(
                            id: field.id,
                            label: Text("\(field.quantity.name) (\(field.quantity.unit))"),
                            assumedDefault: field.assumedDefault,
                            savedValue: field.savedValue,
                            origin: field.observationOrigin,
                            feedback: field.feedback,
                            text: Binding(
                                get: { session.quantityText(field.id, on: day) },
                                set: { text in
                                    guard text != session.quantityText(field.id, on: day) else { return }
                                    session.editQuantity(field.id, on: day, text: text)
                                }
                            ),
                            focus: $focusedVariable,
                            validationMessage: "Enter a valid number.",
                            retry: { session.retryQuantity(field.id, on: day) }
                        )
                    }
                    ForEach(variables) { field in
                        typedRow(field, on: day)
                    }
                } header: {
                    let format = Date.FormatStyle(date: .complete, locale: locale, calendar: calendar, timeZone: .gmt)
                    Text(day.date(in: .gmt), format: format)
                        .accessibilityIdentifier("selectedLogDate")
                }
                if hasFields {
                    dayReview(day)
                }
            }
            .id(day)
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Log Categories", systemImage: "list.bullet") {
                    focusedVariable = nil
                    showingCategories = true
                }
            }
        }
        .sheet(isPresented: $showingCategories) {
            LogCategoriesView(session: $session, selectedDay: day)
        }
        .onChange(of: day) { focusedVariable = nil }
    }

    @ViewBuilder
    private func typedRow(_ field: TypedLogField, on day: LogDay) -> some View {
        let retry = { session.retryTypedEdit(field.id, on: day) }
        if case .count = field.variable.kind {
            LogNumberRow(
                id: field.id,
                label: field.variable.label,
                assumedDefault: countLabel(field.assumedDefault),
                savedValue: countLabel(field.observation?.value),
                origin: field.observation?.origin,
                feedback: field.feedback,
                text: Binding(
                    get: { session.countText(field.id, on: day) },
                    set: { text in
                        guard text != session.countText(field.id, on: day) else { return }
                        session.editCount(field.id, on: day, text: text)
                    }
                ),
                focus: $focusedVariable,
                keyboard: .numberPad,
                validationMessage: "Enter a nonnegative whole number.",
                retry: retry
            )
        } else {
            LogChoiceRow(field: field, retry: retry) { choice in
                focusedVariable = nil
                session.editTypedValue(field.id, on: day, value: choice)
            }
        }
    }

    private func countLabel(_ value: LogValue?) -> String? {
        guard case .count(let count) = value else { return nil }
        return session.formatCount(count)
    }

    @ViewBuilder
    private func dayReview(_ day: LogDay) -> some View {
        let isConfirmed = session.logStatus(on: day) == .confirmed
        if let confirmation = session.dayConfirmation(on: day) {
            Section {
                let title: LocalizedStringKey = if confirmation.saveFailed {
                    "Retry Confirmation"
                } else if isConfirmed {
                    "Confirm New Values"
                } else {
                    "Confirm Day"
                }
                Button(title) {
                    focusedVariable = nil
                    session.confirmDay(day)
                }
                .disabled(!confirmation.canSave)
            } footer: {
                if confirmation.saveFailed {
                    Text("Couldn’t save the day confirmation.")
                        .foregroundStyle(.red)
                }
            }
        } else if isConfirmed {
            Section {
                Label("Day confirmed", systemImage: "checkmark")
            }
        }
    }
}

private struct LogNumberRow: View {
    let id: UUID
    let label: Text
    let assumedDefault: String?
    let savedValue: String?
    let origin: LogObservationOrigin?
    let feedback: LogEditFeedback?
    @Binding var text: String
    var focus: FocusState<UUID?>.Binding
    var keyboard: UIKeyboardType = .numbersAndPunctuation
    let validationMessage: LocalizedStringKey
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            label.accessibilityHidden(true)
            TextField("Value", text: $text, prompt: assumedDefault.map(Text.init(verbatim:)) ?? Text("Enter value"))
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .focused(focus, equals: id)
                .onSubmit { focus.wrappedValue = nil }
                .accessibilityLabel(label)
            LogRowFeedback(
                assumedDefault: assumedDefault.map(Text.init(verbatim:)),
                savedValue: savedValue.map(Text.init(verbatim:)),
                origin: origin, feedback: feedback, validationMessage: validationMessage, retry: retry
            )
        }
    }
}

private struct LogChoiceRow: View {
    let field: TypedLogField
    let retry: () -> Void
    let select: (LogValue) -> Void

    var body: some View {
        let choices = field.variable.kind.choices
        let value = field.pendingValue ?? field.observation?.value ?? field.assumedDefault
        let selection = choices.first(where: { $0.value == value })?.label ?? Text("Choose")

        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(choices) { choice in
                    Button {
                        select(choice.value)
                    } label: {
                        if value == choice.value {
                            Label { choice.label } icon: { Image(systemName: "checkmark") }
                        } else {
                            choice.label
                        }
                    }
                }
            } label: {
                HStack {
                    field.variable.label.foregroundStyle(.primary)
                    Spacer()
                    selection
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .accessibilityLabel(field.variable.label)
            .accessibilityValue(selection)
            LogRowFeedback(
                assumedDefault: choices.first(where: { $0.value == field.assumedDefault })?.label,
                savedValue: choices.first(where: { $0.value == field.observation?.value })?.label,
                origin: field.observation?.origin, feedback: field.feedback, validationMessage: "Choose a value.", retry: retry
            )
        }
    }
}

private struct LogRowFeedback: View {
    let assumedDefault: Text?
    let savedValue: Text?
    let origin: LogObservationOrigin?
    let feedback: LogEditFeedback?
    let validationMessage: LocalizedStringKey
    let retry: () -> Void

    var body: some View {
        if let valueOrigin {
            valueOrigin.font(.footnote).foregroundStyle(.secondary)
        }
        switch feedback {
        case .invalidNumber:
            Text(validationMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        case .saveFailed:
            Text("Couldn’t save this value.")
                .font(.footnote)
                .foregroundStyle(.red)
            Button("Retry Save", action: retry)
                .buttonStyle(.bordered)
        case nil:
            EmptyView()
        }
    }

    private var valueOrigin: Text? {
        if let assumedDefault {
            return feedback == nil ? Text("Default value") : Text("Default value (\(assumedDefault))")
        }
        if let savedValue, feedback != nil {
            return origin == .confirmedDefault
                ? Text("Saved confirmed default (\(savedValue))")
                : Text("Last saved value (\(savedValue))")
        }
        return origin == .confirmedDefault ? Text("Confirmed default") : nil
    }
}

private struct WeekStrip: View {
    let selection: LogDay
    let status: (LogDay) -> LogDayStatus
    let select: (LogDay) -> Void
    @Environment(\.calendar) private var calendar
    @State private var week = 0
    @State private var oldestWeek = -4
    @ScaledMetric private var stripHeight: CGFloat = 60
    @ScaledMetric private var indicatorHeight: CGFloat = 14

    var body: some View {
        let today = calendar.startOfDay(for: .now)
        TabView(selection: $week) {
            ForEach(oldestWeek...0, id: \.self) { weekIndex in
                HStack(spacing: 0) {
                    ForEach(0..<7) { column in
                        let offset = weekIndex * 7 + column - 6
                        if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                            dayButton(day, offset: offset)
                        }
                    }
                }
                .tag(weekIndex)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: stripHeight)
        .padding(.horizontal)
        .onAppear { showSelectedWeek(relativeTo: today) }
        .onChange(of: selection) { showSelectedWeek(relativeTo: today) }
        .onChange(of: week) {
            if week == oldestWeek { oldestWeek -= 4 }
        }
    }

    private func showSelectedWeek(relativeTo today: Date) {
        let selectedDate = calendar.startOfDay(for: selection.date(in: calendar.timeZone))
        let daysAgo = calendar.dateComponents([.day], from: selectedDate, to: today).day ?? 0
        let selectedWeek = -max(0, daysAgo) / 7
        oldestWeek = min(oldestWeek, selectedWeek - 4)
        week = selectedWeek
    }

    private func dayButton(_ date: Date, offset: Int) -> some View {
        let day = LogDay(date, timeZone: calendar.timeZone)
        let selected = day == selection
        let status = status(day)
        let accessibilityStatus: LocalizedStringKey = switch status {
        case .unmarked: "No saved edits"
        case .editsSaved: "Edits saved"
        case .confirmed: "Day confirmed"
        }

        return Button {
            select(day)
        } label: {
            VStack(spacing: 2) {
                Text(date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption)
                Text(date, format: .dateTime.day())
                    .font(.body.weight(selected ? .bold : .regular))
                ZStack {
                    if status == .confirmed {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.semibold))
                    } else if status == .editsSaved {
                        Circle().frame(width: 5, height: 5)
                    }
                }
                .frame(height: indicatorHeight)
                .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: .capsule)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year()))
        .accessibilityValue(Text(accessibilityStatus))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("logDay-\(-offset)")
    }
}
