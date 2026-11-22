import HealthAnalysisCore
import SwiftUI

extension HealthMetricPresentation {
    @MainActor
    static let sleep = Self(
        metric: .sleepAnalysis,
        title: "Sleep",
        recordCountTitle: "Sleep episodes",
        firstDateTitle: "First wake date",
        latestDateTitle: "Latest wake date"
    )
}

struct SleepHistoryRows: View {
    let episodes: [SleepEpisode]

    var body: some View {
        ForEach(episodes) { episode in
            let date = dateFormat(in: episode.timeZone)
            let time = date.hour().minute()
            VStack(alignment: .leading, spacing: 4) {
                Text("Wake date: \(episode.wakeTime, format: date)")
                    .font(.headline)
                    .accessibilityIdentifier("sleep.wakeDate")
                Text(Duration.seconds(episode.duration), format: .units(allowed: [.hours, .minutes, .seconds], width: .wide))
                Group {
                    Text("Sleep started: \(episode.startDate, format: time)")
                    Text("Wake time: \(episode.wakeTime, format: time)")
                    Text(episode.source.name)
                    switch episode.timeZoneEvidence {
                    case .sampleMetadata(let identifier, _):
                        Text("Time zone: \(identifier)")
                    case .importTimeZone(let identifier):
                        Text("Time zone assumed at import: \(identifier)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func dateFormat(in timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        format.timeZone = timeZone
        return format
    }
}

struct SleepHistoryUnavailable: View {
    let hasRecords: Bool
    let hasSelectedSource: Bool

    var body: some View {
        if hasRecords {
            Text("Insufficient asleep records to determine sleep duration or timing.")
        } else if hasSelectedSource {
            Text("No imported sleep records for this source.")
        } else {
            Text("No readable sleep records")
        }
    }
}
