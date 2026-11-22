import HealthAnalysisCore
import SwiftUI

struct CountObservationView: View {
    let result: AnalysisResult
    let observation: AnalysisObservation

    var body: some View {
        List {
            if let output = result.outputVariable, let origin = observation.outputOrigin,
               case .count(let count)? = observation.outputTrackingValue {
                Section("Output") {
                    countRow(name: output.name, value: count, date: observation.outputDate, origin: origin)
                }
            }
            Section("Inputs and adjustments") {
                ForEach(observation.inputs, id: \.series) { value in
                    if let input = result.modeledInputs.first(where: { $0.series == value.series }),
                       case .count(let count)? = value.trackingValue {
                        countRow(name: input.name, value: count, date: value.date, origin: value.origin)
                    }
                }
            }
        }
        .navigationTitle("Paired counts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func countRow(name: String, value: Int, date: Date, origin: ManualValueOrigin) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(name) {
                Text(value, format: .number)
            }
            Text(date, format: dayFormat)
            switch origin {
            case .observation:
                Text("Recorded count")
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
