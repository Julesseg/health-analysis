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
                    valueRow(name: output.name, value: value, date: observation.outputDate, origin: origin)
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
                        valueRow(name: input.name, value: tracked, date: value.date, origin: value.origin)
                    }
                }
            }
        }
        .navigationTitle(countOnly ? "Paired counts" : "Paired values")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func valueRow(name: String, value: ManualTrackingValue, date: Date, origin: ManualValueOrigin) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(name) {
                switch value {
                case .count(let count), .rating(let count): Text(count, format: .number)
                case .yesNo(let isYes): yesNoLabel(isYes)
                case .timeOfDay(let time, _): analysisClockText(Double(time.hour * 60 + time.minute))
                default: EmptyView()
                }
            }
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
