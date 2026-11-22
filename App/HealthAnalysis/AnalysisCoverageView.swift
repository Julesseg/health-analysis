import HealthAnalysisCore
import SwiftUI

struct AnalysisCoverageView: View {
    let result: AnalysisResult
    let application: HealthAnalysisApplication

    var body: some View {
        List {
            Section("Question") {
                LabeledContent("Output") { result.analysisOutputTitle }
                ExploreTemporalSummary(configuration: result.configuration)
                LabeledContent("Analysis time zone", value: result.configuration.timeZone.identifier)
                if result.configuration.output.isSleepDuration {
                    Text("Each recorded wake date uses its longest completed sleep episode. Each input uses complete days before the episode began.")
                } else {
                    Text("Each input uses complete local days before the resting heart rate sample began.")
                }
                if result.configuration.behaviorWindow != .precedingDay {
                    Text("Each quantity is totaled across the selected window.")
                }
                if result.configuration.history != .fullHistory {
                    Text("History limits output dates. Earlier inputs can still complete a window.")
                }
            }
            Section("Sources") {
                if let source = result.outputSource ?? result.inspection?.unpairedOutputs.first?.source {
                    LabeledContent("Output source", value: source.name)
                    LabeledContent("Source identifier", value: source.bundleIdentifier)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Source identifier")
                        .accessibilityValue(Text(source.bundleIdentifier))
                        .accessibilityIdentifier("explore.outputSource")
                } else if let identifier = selectedSourceIdentifier {
                    LabeledContent("Selected source identifier", value: identifier)
                }
                if let lastRead = result.healthHistoryReadAt {
                    LabeledContent("Last successful Health check") {
                        Text(lastRead, format: result.analysisDateFormat.hour().minute())
                    }
                }
                if result.coverage.outputDayCount == 0 {
                    Text("No output measurements are available for this result.")
                    NavigationLink("Check Health access and sources") {
                        HealthAccessAndSourcesView(history: application.healthMeasurements)
                    }
                }
            }
            Section("Overlap") {
                LabeledContent("Paired output days", value: result.coverage.usableDates.count.formatted())
                LabeledContent("Output days in selected history", value: result.coverage.outputDayCount.formatted())
                LabeledContent("Distinct behavior days", value: result.coverage.distinctBehaviorDayCount.formatted())
                LabeledContent("Nonoverlapping windows", value: result.coverage.nonOverlappingWindowCount.formatted())
                if let first = result.coverage.firstDate, let last = result.coverage.lastDate {
                    LabeledContent("Usable history") {
                        dateRange(first, last)
                    }
                }
            }
            Section("Gaps") {
                LabeledContent(
                    "Output days without a complete input",
                    value: result.coverage.outputDaysWithoutCompleteInput.formatted()
                )
                if let unpaired = result.inspection?.unpairedOutputs, !unpaired.isEmpty {
                    NavigationLink("Inspect missing input dates") {
                        missingInputDates(unpaired)
                    }
                } else if result.coverage.outputDaysWithoutCompleteInput > 0 {
                    Text("Refresh this analysis to inspect the missing input dates.")
                    ForEach(result.coverage.outputDatesWithoutCompleteInput, id: \.self) {
                        Text($0, format: result.analysisDateFormat)
                    }
                }
                if !result.coverage.usableDates.isEmpty && result.coverage.gaps.isEmpty {
                    Text("No gaps between usable dates.")
                }
                ForEach(result.coverage.gaps) { gap in
                    dateRange(gap.firstDate, gap.lastDate)
                }
            }
            Section("Usable dates") {
                if result.coverage.usableDates.isEmpty {
                    Text("No paired days.")
                }
                ForEach(result.coverage.usableDates, id: \.self) {
                    Text($0, format: result.analysisDateFormat)
                }
            }
        }
        .navigationTitle("Usable dates and gaps")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedSourceIdentifier: String? {
        if let stored = result.inspection?.selectedOutputSourceIdentifier { return stored }
        if case .health(_, let identifier) = result.configuration.output { return identifier }
        return nil
    }

    private func dateRange(_ first: Date, _ last: Date) -> Text {
        let format = result.analysisDateFormat
        if first == last { return Text(first, format: format) }
        return Text("\(first, format: format) – \(last, format: format)")
    }

    private func missingInputDates(_ outputs: [AnalysisInspection.OutputWithoutPair]) -> some View {
        List {
            ForEach(outputs) { output in
                Section {
                    LabeledContent("Output value") { result.analysisOutputValue(output.value) }
                    if output.missingInputs.isEmpty {
                        Text("A complete input window could not be prepared for this measurement.")
                    }
                    ForEach(output.missingInputs) { missing in
                        if let input = result.modeledInputs.first(where: { $0.series == missing.series }) {
                            NavigationLink {
                                ManualLogView(
                                    log: application.manualLog,
                                    initialDay: ManualLogDay(missing.date, timeZone: result.configuration.timeZone)
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(input.name)
                                    Text("No usable input on \(missing.date, format: result.analysisDateFormat)")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            .accessibilityIdentifier("explore.missingInput")
                        }
                    }
                } header: {
                    Text(output.date, format: result.analysisDateFormat)
                }
            }
        }
        .navigationTitle("Missing input dates")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AnalysisOutputValuesView: View {
    let result: AnalysisResult

    var body: some View {
        List(result.inspectedOutputs) { output in
            VStack(alignment: .leading, spacing: 4) {
                Text(output.date, format: result.analysisDateFormat)
                result.analysisOutputValue(output.value)
                if let source = output.source {
                    Text(source.name)
                }
                Text(output.anchor, format: result.analysisDateFormat.hour().minute())
                Text(output.paired ? "Paired in this analysis" : "No complete input window")
            }
            .accessibilityElement(children: .combine)
        }
        .navigationTitle("Output dates and values")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AnalysisInspectedOutput: Identifiable {
    var id: Date { date }
    let date: Date
    let anchor: Date
    let value: Double
    let source: HealthMeasurement.Source?
    let paired: Bool
}

extension AnalysisResult {
    var analysisCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = configuration.timeZone
        return calendar
    }

    var analysisDateFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        format.timeZone = configuration.timeZone
        return format
    }

    @MainActor var analysisOutputTitle: Text {
        if configuration.output.isSleepDuration { return Text("Sleep duration") }
        if case .health(let metric, _) = configuration.output,
           let presentation = HealthMetricPresentation.supported.first(where: { $0.metric == metric }) {
            return Text(presentation.title)
        }
        return Text("Output")
    }

    @MainActor var analysisOutputAxis: Text {
        configuration.output.isSleepDuration ? Text("Sleep duration (hours)") : Text("\(analysisOutputTitle) (bpm)")
    }

    func analysisOutputValue(_ value: Double) -> Text {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
        return configuration.output.isSleepDuration
            ? Text("\(value, format: format) h")
            : Text("\(value, format: format) bpm")
    }

    var inspectedOutputs: [AnalysisInspectedOutput] {
        let paired = observations.map {
            AnalysisInspectedOutput(date: $0.outputDate, anchor: $0.outputAnchor, value: $0.outputValue, source: outputSource, paired: true)
        }
        let unpaired = (inspection?.unpairedOutputs ?? []).map {
            AnalysisInspectedOutput(date: $0.date, anchor: $0.anchor, value: $0.value, source: $0.source, paired: false)
        }
        return (paired + unpaired).sorted { $0.date < $1.date }
    }
}
