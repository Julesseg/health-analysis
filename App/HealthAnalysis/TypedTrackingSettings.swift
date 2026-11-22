import HealthAnalysisCore
import SwiftUI

struct TypedTrackingSettings: View {
    let log: ManualLog

    var body: some View {
        ForEach(log.typedVariables) { variable in
            NavigationLink {
                TypedTrackingDefaultsView(log: log, variable: variable)
            } label: {
                LabeledContent {
                    Text(variable.kind.title)
                } label: {
                    Text(verbatim: variable.name)
                }
            }
        }
        ForEach(TypedTrackingKind.allCases) { kind in
            NavigationLink(kind.addTitle) {
                CreateTypedTrackingVariableView(log: log, kind: kind)
            }
        }
    }
}

enum TypedTrackingKind: CaseIterable, Identifiable {
    case count
    case yesNo
    case rating
    case category
    case timeOfDay

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .count: "Count"
        case .yesNo: "Yes/no"
        case .rating: "Rating"
        case .category: "Category"
        case .timeOfDay: "Time of day"
        }
    }

    var addTitle: LocalizedStringKey {
        switch self {
        case .count: "Add count"
        case .yesNo: "Add yes/no"
        case .rating: "Add rating"
        case .category: "Add category"
        case .timeOfDay: "Add time of day"
        }
    }

    var creationTitle: LocalizedStringKey {
        switch self {
        case .count: "New count"
        case .yesNo: "New yes/no"
        case .rating: "New rating"
        case .category: "New category"
        case .timeOfDay: "New time of day"
        }
    }
}

private extension TrackingVariableKind {
    var title: LocalizedStringKey {
        switch self {
        case .count: TypedTrackingKind.count.title
        case .yesNo: TypedTrackingKind.yesNo.title
        case .rating: TypedTrackingKind.rating.title
        case .category: TypedTrackingKind.category.title
        case .timeOfDay: TypedTrackingKind.timeOfDay.title
        }
    }
}

struct CreateTypedTrackingVariableView: View {
    let log: ManualLog
    let kind: TypedTrackingKind
    private let suggestion: SuggestedTrackingVariable?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @State private var name = ""
    @State private var startDate = Date.now
    @State private var count = "0"
    @State private var yesNo = false
    @State private var minimumRating = "1"
    @State private var maximumRating = "5"
    @State private var rating = "3"
    @State private var categories = [CategoryDraft(), CategoryDraft()]
    @State private var selectedCategoryID: TrackingCategory.ID?
    @State private var defaultTime = ManualClockTime(hour: 12, minute: 0)
    @State private var didFailToSave = false

    init(log: ManualLog, kind: TypedTrackingKind, suggestion: SuggestedTrackingVariable? = nil, name: String = "") {
        self.log = log
        self.kind = kind
        self.suggestion = suggestion
        _name = State(initialValue: name)
    }

    private struct CategoryDraft: Identifiable {
        let id = UUID()
        var name = ""
    }

    private var options: [TrackingCategory] {
        categories.map { TrackingCategory(id: $0.id, name: $0.name) }
    }

    private var namedOptions: [TrackingCategory] {
        options.filter { !$0.name.isEmpty }
    }

    private var defaultCategoryID: TrackingCategory.ID? {
        namedOptions.first { $0.id == selectedCategoryID }?.id ?? namedOptions.first?.id
    }

    private var definition: (kind: TrackingVariableKind, defaultValue: ManualTrackingValue)? {
        switch kind {
        case .count:
            guard let count = wholeNumber(count), count >= 0 else { return nil }
            return (.count, .count(count))
        case .yesNo:
            return (.yesNo, .yesNo(yesNo))
        case .rating:
            guard let minimum = wholeNumber(minimumRating), let maximum = wholeNumber(maximumRating),
                minimum < maximum, let rating = wholeNumber(rating), (minimum...maximum).contains(rating)
            else { return nil }
            return (.rating(minimum...maximum), .rating(rating))
        case .category:
            guard let defaultCategoryID else { return nil }
            let kind = TrackingVariableKind.category(options)
            let value = ManualTrackingValue.category(defaultCategoryID)
            return kind.accepts(value) ? (kind, value) : nil
        case .timeOfDay:
            return (.timeOfDay, .timeOfDay(defaultTime))
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                configurationFields
            }
            Section {
                ManualLogDatePicker(title: "Start date", date: $startDate)
            }
            if didFailToSave {
                Section {
                    Text("Couldn’t add this tracking variable. Try again.").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(kind.creationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: addVariable)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || definition == nil)
            }
        }
    }

    @ViewBuilder
    private var configurationFields: some View {
        switch kind {
        case .count:
            TextField("Default count", text: $count)
                .keyboardType(.numberPad)
            if definition == nil {
                validation("Enter a whole number of zero or more.")
            }
        case .yesNo:
            Toggle("Default value", isOn: $yesNo)
        case .rating:
            TextField("Minimum rating", text: $minimumRating)
                .keyboardType(.numbersAndPunctuation)
            TextField("Maximum rating", text: $maximumRating)
                .keyboardType(.numbersAndPunctuation)
            TextField("Default rating", text: $rating)
                .keyboardType(.numbersAndPunctuation)
            if definition == nil {
                validation("Enter whole numbers, with a minimum below the maximum and a default within that range.")
            }
        case .category:
            categoryFields
        case .timeOfDay:
            ManualClockPicker(label: Text("Default time"), time: $defaultTime)
        }
    }

    @ViewBuilder
    private var categoryFields: some View {
        ForEach($categories) { $category in
            let index = categories.firstIndex { $0.id == category.id } ?? 0
            TextField("Category \(index + 1)", text: $category.name)
                .deleteDisabled(categories.count <= 2)
        }
        .onDelete { categories.remove(atOffsets: $0) }
        Button("Add category option", systemImage: "plus") { categories.append(CategoryDraft()) }

        if let defaultCategoryID {
            Picker("Default category", selection: Binding(
                get: { self.defaultCategoryID ?? defaultCategoryID },
                set: { selectedCategoryID = $0 }
            )) {
                ForEach(namedOptions) { option in
                    Text(verbatim: option.name).tag(option.id)
                }
            }
            .pickerStyle(.menu)
        }
        if definition == nil {
            validation("Enter a different name for each category.")
        }
    }

    private func validation(_ message: LocalizedStringKey) -> some View {
        Text(message).foregroundStyle(.red).font(.footnote)
    }

    private func wholeNumber(_ text: String) -> Int? {
        guard let value = QuantityNumber.parse(text, locale: locale) else { return nil }
        return Int(NSDecimalNumber(decimal: value).stringValue)
    }

    private func addVariable() {
        guard let definition else { return }
        do {
            try log.createTypedVariable(
                name: name,
                kind: definition.kind,
                defaultValue: definition.defaultValue,
                startsOn: ManualLogDay(startDate, timeZone: timeZone),
                suggestion: suggestion
            )
            dismiss()
        } catch {
            didFailToSave = true
        }
    }
}
