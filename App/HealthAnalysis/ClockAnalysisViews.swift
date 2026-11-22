import HealthAnalysisCore
import SwiftUI

func analysisClockText(_ minute: Double) -> Text {
    var style = Date.FormatStyle.dateTime.hour().minute()
    style.timeZone = .gmt
    return Text(Date(timeIntervalSince1970: minute * 60), format: style)
}

extension SleepTiming {
    var title: LocalizedStringKey {
        switch self {
        case .onset: "Sleep onset time"
        case .wake: "Wake time"
        }
    }
}

extension AnalysisModeledInput {
    var isClock: Bool { kind == .tracked(.timeOfDay) }
}

extension AnalysisResult {
    var isClockOutput: Bool { outputVariable?.kind == .tracked(.timeOfDay) }

    func clockInterval(for id: AnalysisSeriesID) -> AnalysisClockInterval? {
        clockIntervals?.first { $0.series == id }
    }
}

struct AnalysisClockPrecisionRow: View {
    let precision: ManualClockPrecision?

    var body: some View {
        if let precision {
            LabeledContent("Time precision") {
                Text(precision == .approximate ? "Approximate time" : "Exact time")
            }
        }
    }
}

struct SleepTimingProvenanceRows: View {
    let anchor: Date
    let evidence: SleepEpisode.TimeZoneEvidence?

    var body: some View {
        if let evidence {
            LabeledContent("Recorded event (UTC)") {
                Text(anchor, format: utcFormat)
            }
            LabeledContent("Sleep time zone", value: evidence.identifier)
            LabeledContent("Time zone source") {
                switch evidence {
                case .sampleMetadata: Text("Health sample")
                case .importTimeZone: Text("Time zone at import")
                }
            }
            LabeledContent("Time precision") { Text("Imported time, shown to the minute") }
        }
    }

    private var utcFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.year().month().day().hour().minute().second()
        style.timeZone = .gmt
        return style
    }
}
