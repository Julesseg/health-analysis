import HealthAnalysisCore
import SwiftUI

struct CategoryContrastSelection {
    var reference: TrackingCategory.ID?
    var comparison: TrackingCategory.ID?

    func contrast(in categories: [TrackingCategory]) -> AnalysisCategoryContrast? {
        guard let reference, let comparison, reference != comparison,
              categories.contains(where: { $0.id == reference }),
              categories.contains(where: { $0.id == comparison }) else { return nil }
        return .init(reference: reference, comparison: comparison)
    }
}

struct CategoryContrastFields: View {
    let categories: [TrackingCategory]
    @Binding var selection: CategoryContrastSelection

    var body: some View {
        Picker("Reference category", selection: $selection.reference) {
            choices(excluding: selection.comparison)
        }
        .accessibilityIdentifier("explore.category.reference")
        Picker("Comparison category", selection: $selection.comparison) {
            choices(excluding: selection.reference)
        }
        .accessibilityIdentifier("explore.category.comparison")
    }

    @ViewBuilder
    private func choices(excluding excluded: TrackingCategory.ID?) -> some View {
        Text("Choose category").tag(nil as TrackingCategory.ID?)
        ForEach(categories.filter { $0.id != excluded }) { category in
            Text(category.name).tag(Optional(category.id))
        }
    }
}

struct AnalysisCategoryEvidenceRows: View {
    let result: AnalysisResult

    var body: some View {
        if let evidence = result.categoryEvidence {
            if let event = result.categoryEvent {
                Section {
                    LabeledContent("Output event", value: event.name)
                    ForEach(evidence.outputLevels) { level in
                        categoryLevel(level)
                    }
                } header: {
                    Text("Output categories")
                } footer: {
                    Text("The comparison includes every other output category.")
                }
            }
            ForEach(result.modeledInputs) { input in
                if let levels = evidence.inputLevels[input.series] {
                    Section(input.name) {
                        ForEach(levels) { level in
                            categoryLevel(level)
                        }
                    }
                }
            }
            if !evidence.inputLevels.isEmpty {
                LabeledContent("Output days outside selected categories") {
                    Text(evidence.excludedOutputDates.count, format: .number)
                }
            }
        }
    }

    private func categoryLevel(_ level: AnalysisCategoryEvidence.Level) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(level.category.name)
            Text("\(level.recordedDayCount) of \(level.pairedDayCount) paired days recorded")
                .foregroundStyle(.secondary)
            if let support = level.eventSupport, let event = result.categoryEvent {
                Text("\(support.eventDayCount) with \(event.name), \(support.otherDayCount) with other categories when both values were recorded")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension AnalysisResult {
    var categoryEvent: TrackingCategory? {
        outputVariable?.categories.first { $0.id == configuration.categories?.outputEvent }
    }

    func categoryContrast(for series: AnalysisSeriesID) -> (reference: String, comparison: String)? {
        guard let selection = configuration.categories?.inputContrasts[series],
              let levels = categoryEvidence?.inputLevels[series],
              let reference = levels.first(where: { $0.id == selection.reference }),
              let comparison = levels.first(where: { $0.id == selection.comparison }) else { return nil }
        return (reference.category.name, comparison.category.name)
    }
}

extension AnalysisModeledInput {
    var categories: [TrackingCategory] {
        guard case .tracked(.category(let categories))? = kind else { return [] }
        return categories
    }

    func displayedValue(_ value: Double, trackingValue: ManualTrackingValue?) -> Text {
        if !categories.isEmpty {
            return categoryValueLabel(trackingValue, categories: categories)
        }
        return Text("\(value, format: .number) \(unit)")
    }
}

func categoryValueLabel(_ value: ManualTrackingValue?, categories: [TrackingCategory]) -> Text {
    if let name = categoryName(value, among: categories) {
        return Text(verbatim: name)
    }
    return Text("Unavailable category")
}

func categoryName(_ value: ManualTrackingValue?, among categories: [TrackingCategory]) -> String? {
    guard case .category(let id)? = value else { return nil }
    return categories.first { $0.id == id }?.name
}
