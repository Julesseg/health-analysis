import Charts
import HealthAnalysisCore
import SwiftUI

struct AnalysisObservedView: View {
    let result: AnalysisResult
    let log: ManualLog
    @State private var selectedInput: AnalysisSeriesID?
    @ScaledMetric private var chartHeight = 175.0

    init(result: AnalysisResult, log: ManualLog, initialInput: AnalysisSeriesID? = nil) {
        self.result = result
        self.log = log
        _selectedInput = State(initialValue: initialInput ?? result.modeledInputs.first?.series)
    }

    var body: some View {
        List {
            Section {
                let outputs = result.outputEvidence.filter(\.isObserved)
                if outputs.isEmpty {
                    Text("No observed output measurements are available for this result.")
                } else {
                    timeline(outputs)
                    NavigationLink("Output dates and values") {
                        AnalysisOutputValuesView(result: result)
                    }
                }
            } header: {
                Text("Observed timeline")
            } footer: {
                if result.outputEvidence.contains(where: { $0.isObserved && !$0.paired }) {
                    Text("Includes output measurements with incomplete input windows.")
                }
            }

            if let input = result.modeledInputs.first(where: { $0.series == selectedInput }) {
                Section {
                    if result.modeledInputs.count > 1 {
                        Picker("Input", selection: $selectedInput) {
                            ForEach(result.modeledInputs) { choice in
                                Text("\(choice.name) (\(choice.unit))").tag(Optional(choice.series))
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .accessibilityIdentifier("explore.observedInput")
                    }
                    let evidence = result.inputEvidence(for: input.series)
                    let points = evidence.observedPairs
                    if points.isEmpty {
                        Text("No pairs with explicit observations for \(input.name) and this output.")
                    } else {
                        scatterplot(points, input: input)
                    }
                    NavigationLink("Input provenance and paired values") {
                        AnalysisInputEvidenceView(result: result, input: input, log: log)
                    }
                } header: {
                    Text("Observed scatterplot")
                } footer: {
                    Text("Each point pairs a complete input window and an output, both explicitly observed.")
                }
            }
        }
        .navigationTitle("Observed measurements")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.timeZone, result.configuration.timeZone)
    }

    private func timeline(_ outputs: [AnalysisOutputEvidence]) -> some View {
        Chart(outputs) { row in
            PointMark(
                x: .value("Output date", row.date),
                y: .value("Observed output", row.value)
            )
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: result.analysisDateFormat)
            }
        }
        .chartYAxisLabel { result.analysisOutputAxis }
        .frame(height: chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Observed timeline for \(result.analysisOutputTitle)"))
        .accessibilityValue(Text("\(outputs.count) output measurements. Dates and values are listed below."))
        .accessibilityIdentifier("explore.observedTimeline")
    }

    private func scatterplot(_ points: [AnalysisInputEvidence.Pair], input: AnalysisModeledInput) -> some View {
        Chart(points) { pair in
            PointMark(
                x: .value("Observed input", pair.input.value),
                y: .value("Observed output", pair.outputValue)
            )
            .opacity(0.65)
        }
        .chartXScale(domain: .automatic(includesZero: false))
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxisLabel { Text("\(input.name) (\(input.unit))") }
        .chartYAxisLabel { result.analysisOutputAxis }
        .frame(height: chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Observed scatterplot for \(input.name) and \(result.analysisOutputTitle)"))
        .accessibilityValue(Text("\(points.count) explicit pairs. Input and output values are listed below."))
        .accessibilityIdentifier("explore.observedScatter")
    }
}

struct AnalysisInputEvidenceView: View {
    let result: AnalysisResult
    let input: AnalysisModeledInput
    let log: ManualLog

    var body: some View {
        let evidence = result.inputEvidence(for: input.series)
        let entries = evidence.distinctEntries
        List {
            Section("Input provenance") {
                if entries.isEmpty {
                    Text("No complete pairs for \(input.name).")
                } else {
                    let explicit = entries.count { $0.origin == .observation }
                    provenanceShare("Explicit observations", count: explicit, total: entries.count)
                    provenanceShare("Assumed defaults", count: entries.count - explicit, total: entries.count)
                    if result.configuration.behaviorWindow != .precedingDay {
                        provenanceShare("Windows using assumed defaults", count: evidence.assumedDefaultCount, total: evidence.pairs.count)
                    }
                    if let approximate = evidence.approximateCount {
                        LabeledContent("Approximate entries", value: approximate.formatted())
                    }
                }
                LabeledContent("Source") { Text("Daily log") }
            }
            if !entries.isEmpty {
                Section("Paired values") {
                    ForEach(evidence.pairs) { pair in
                        NavigationLink {
                            pairDetails(pair)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pair.outputDate, format: result.analysisDateFormat)
                                Text("\(pair.input.value, format: .number) \(input.unit) and \(result.analysisOutputValue(pair.outputValue))")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .navigationTitle(input.name)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.timeZone, result.configuration.timeZone)
    }

    private func provenanceShare(_ title: LocalizedStringKey, count: Int, total: Int) -> some View {
        LabeledContent(title) {
            Text("\(count) of \(total) (\(Double(count) / Double(total), format: .percent.precision(.fractionLength(0))))")
        }
    }

    private func pairDetails(_ pair: AnalysisInputEvidence.Pair) -> some View {
        List {
            Section("Output measurement") {
                LabeledContent {
                    result.analysisOutputValue(pair.outputValue)
                } label: {
                    result.analysisOutputTitle
                }
                LabeledContent("Output date") { Text(pair.outputDate, format: result.analysisDateFormat) }
                if let source = result.outputSource {
                    LabeledContent("Source", value: source.name)
                }
                AnalysisOutputProvenanceRows(result: result, origin: pair.outputOrigin)
            }
            Section("Input window") {
                LabeledContent(input.name) { Text("\(pair.input.value, format: .number) \(input.unit)") }
            }
            ForEach(pair.entries, id: \.date) { entry in
                entryDetails(entry)
            }
        }
        .navigationTitle("Paired values")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func entryDetails(_ entry: AnalysisObservation.Input.Day) -> some View {
        Section {
            LabeledContent(input.name) { Text("\(entry.value, format: .number) \(input.unit)") }
            switch entry.origin {
            case .observation:
                LabeledContent("Provenance") { Text("Explicit observation") }
            case .assumedDefault(let effectiveOn):
                LabeledContent("Provenance") { Text("Assumed default") }
                if let date = result.analysisCalendar.date(from: DateComponents(
                    year: effectiveOn.year, month: effectiveOn.month, day: effectiveOn.day
                )) {
                    LabeledContent("Default effective from") { Text(date, format: result.analysisDateFormat) }
                }
            }
            if let precision = entry.clockPrecision {
                LabeledContent("Time precision") {
                    Text(precision == .approximate ? "Approximate time" : "Exact time")
                }
            }
            NavigationLink("Open daily log") {
                ManualLogView(log: log, initialDay: ManualLogDay(entry.date, timeZone: result.configuration.timeZone))
            }
        } header: {
            Text(entry.date, format: result.analysisDateFormat)
        }
    }
}
