import HealthAnalysisCore
import SwiftUI

struct LogView: View {
    @Binding var session: HealthAnalysisSession
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var showingCategories = false
    @FocusState private var focusedQuantity: UUID?

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
        let fields = session.logFields(on: day)

        return VStack(alignment: .leading) {
            WeekStrip(
                selection: day,
                hasSavedEdits: { session.hasSavedEdits(on: $0) },
                select: { session.selectLogDay($0) }
            )
            Form {
                Section {
                    if fields.isEmpty {
                        if session.quantities.isEmpty {
                            Text("No tracking variables configured.")
                        } else {
                            Text("No tracking variables for this day.")
                        }
                    }
                    ForEach(fields) { field in
                        QuantityRow(
                            field: field,
                            text: session.quantityText(field.id, on: day),
                            focus: $focusedQuantity,
                            edit: { session.editQuantity(field.id, on: day, text: $0) },
                            retry: { session.retryQuantity(field.id, on: day) }
                        )
                    }
                } header: {
                    let format = Date.FormatStyle(date: .complete, locale: locale, calendar: calendar, timeZone: .gmt)
                    Text(day.date(in: .gmt), format: format)
                        .accessibilityIdentifier("selectedLogDate")
                }
            }
            .id(day)
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Log Categories", systemImage: "list.bullet") {
                    focusedQuantity = nil
                    showingCategories = true
                }
            }
        }
        .sheet(isPresented: $showingCategories) {
            LogCategoriesView(session: $session, selectedDay: day)
        }
        .onChange(of: day) { focusedQuantity = nil }
    }
}

private struct QuantityRow: View {
    let field: LogQuantityField
    @State var text: String
    var focus: FocusState<UUID?>.Binding
    let edit: (String) -> Void
    let retry: () -> Void

    var body: some View {
        let label = Text("\(field.quantity.name) (\(field.quantity.unit))")
        let input = Binding(
            get: { text },
            set: { value in
                text = value
                edit(value)
            }
        )

        VStack(alignment: .leading, spacing: 6) {
            label.accessibilityHidden(true)
            TextField("Value", text: input, prompt: field.assumedDefault.map(Text.init(verbatim:)) ?? Text("Enter value"))
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .focused(focus, equals: field.id)
                .onSubmit { focus.wrappedValue = nil }
                .accessibilityLabel(label)
            switch field.feedback {
            case .invalidNumber:
                Text("Enter a valid number.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            case .saveFailed:
                Text("Couldn’t save this value.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("Retry Save", action: retry)
                    .buttonStyle(.bordered)
            case nil:
                if field.assumedDefault != nil {
                    Text("Default value")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct WeekStrip: View {
    let selection: LogDay
    let hasSavedEdits: (LogDay) -> Bool
    let select: (LogDay) -> Void
    @Environment(\.calendar) private var calendar
    @State private var week = 0
    @State private var oldestWeek = -4
    @ScaledMetric private var stripHeight: CGFloat = 60

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
        let edited = hasSavedEdits(day)

        return Button {
            select(day)
        } label: {
            VStack(spacing: 2) {
                Text(date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption)
                Text(date, format: .dateTime.day())
                    .font(.body.weight(selected ? .bold : .regular))
                Circle()
                    .fill(.tint)
                    .frame(width: 5, height: 5)
                    .opacity(edited ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: .capsule)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year()))
        .accessibilityValue(edited ? Text("Edits saved") : Text("No saved edits"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("logDay-\(-offset)")
    }
}
