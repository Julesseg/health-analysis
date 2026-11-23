import HealthAnalysisCore
import SwiftUI

struct PairedObservationView: View {
    let result: AnalysisResult
    let observation: AnalysisObservation
    let countOnly: Bool

    var body: some View {
        List {
            if let output = result.outputVariable, let origin = observation.outputOrigin,
               let value = observation.outputTrackingValue {
                Section("Output") {
                    valueRow(name: output.name, categories: output.categories, value: value, date: observation.outputDate, origin: origin)
                }
            }
            if let evidence = observation.sleepTimeZoneEvidence {
                Section("Output") {
                    LabeledContent { result.analysisOutputValue(observation.outputValue, trackingValue: nil) } label: {
                        result.analysisOutputTitle
                    }
                    SleepTimingProvenanceRows(anchor: observation.outputAnchor, evidence: evidence)
                }
            }
            Section("Inputs and adjustments") {
                ForEach(observation.inputs, id: \.series) { value in
                    if let input = result.modeledInputs.first(where: { $0.series == value.series }),
                       let tracked = value.trackingValue {
                        valueRow(name: input.name, categories: input.categories, value: tracked, date: value.date, origin: value.origin)
                    }
                }
            }
        }
        .navigationTitle(countOnly ? "Paired counts" : "Paired values")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func valueRow(
        name: String, categories: [TrackingCategory], value: ManualTrackingValue, date: Date, origin: ManualValueOrigin
    ) -> some View {
        let displayedValue = valueLabel(value, categories: categories)
        return VStack(alignment: .leading) {
            LabeledContent(name) { displayedValue }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: name))
                .accessibilityValue(displayedValue)
                .accessibilityIdentifier("explore.pairedValue")
            Text(date, format: dayFormat)
            if case .timeOfDay(_, let precision) = value {
                AnalysisClockPrecisionRow(precision: precision)
            }
            switch origin {
            case .observation:
                if case .count = value {
                    Text("Recorded count")
                } else {
                    Text("Explicit observation")
                }
            case .assumedDefault(let effectiveOn):
                if let date = effectiveDate(effectiveOn) {
                    Text("Assumed default effective \(date, format: dayFormat)")
                } else {
                    Text("Assumed default")
                }
            }
        }
    }

    private func valueLabel(_ value: ManualTrackingValue, categories: [TrackingCategory]) -> Text {
        switch value {
        case .count(let count), .rating(let count): Text(count, format: .number)
        case .yesNo(let isYes): yesNoLabel(isYes)
        case .category: categoryValueLabel(value, categories: categories)
        case .timeOfDay(let time, _): analysisClockText(Double(time.hour * 60 + time.minute))
        }
    }

    private var dayFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        format.timeZone = result.configuration.timeZone
        return format
    }

    private func effectiveDate(_ day: ManualLogDay) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = result.configuration.timeZone
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
    }
}
