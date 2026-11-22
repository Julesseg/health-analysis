import Foundation

enum SleepDerivation {
    private static let maximumInterruption: TimeInterval = 90 * 60

    private struct Boundary {
        let date: Date
        let sample: HealthMeasurement
        let asleep: Bool
        let isStart: Bool
    }

    private struct Episode {
        let start: Date
        var end: Date
        var duration: TimeInterval
        var zone: SleepEpisode.TimeZoneEvidence?
        let onsetZone: SleepEpisode.TimeZoneEvidence?
    }

    static func episodes(from records: [HealthMeasurement], fallback: TimeZone) -> [SleepEpisode] {
        let sources = Dictionary(grouping: records, by: \.source.bundleIdentifier)
        return sources.values.flatMap { episodes(for: $0, fallback: fallback) }.sorted {
            if $0.wakeTime == $1.wakeTime {
                return $0.source.bundleIdentifier < $1.source.bundleIdentifier
            }
            return $0.wakeTime > $1.wakeTime
        }
    }

    static func coverage(for episodes: [SleepEpisode]) -> HealthMeasurementHistory.Coverage? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let dates = episodes.compactMap { episode in
            calendar.date(from: episode.wakeDay).map { (day: $0, episode: episode) }
        }
        guard let first = dates.min(by: { ($0.day, $0.episode.wakeTime) < ($1.day, $1.episode.wakeTime) }),
              let latest = dates.max(by: { ($0.day, $0.episode.wakeTime) < ($1.day, $1.episode.wakeTime) }) else { return nil }
        let measuredDays = Set(dates.map(\.day)).count
        let span = (calendar.dateComponents([.day], from: first.day, to: latest.day).day ?? 0) + 1
        return HealthMeasurementHistory.Coverage(
            recordCount: episodes.count,
            firstMeasurement: first.episode.wakeTime,
            latestMeasurement: latest.episode.wakeTime,
            firstMeasurementTimeZone: first.episode.timeZone,
            latestMeasurementTimeZone: latest.episode.timeZone,
            measuredDays: measuredDays,
            daysWithoutMeasurements: max(0, span - measuredDays)
        )
    }

    private static func episodes(for records: [HealthMeasurement], fallback: TimeZone) -> [SleepEpisode] {
        guard let source = records.first?.source else { return [] }
        let boundaries = records.flatMap { sample -> [Boundary] in
            guard let stage = sample.sleepStage, stage.isAsleep || stage == .awake,
                  sample.startDate < sample.endDate else { return [] }
            return [
                Boundary(date: sample.startDate, sample: sample, asleep: stage.isAsleep, isStart: true),
                Boundary(date: sample.endDate, sample: sample, asleep: stage.isAsleep, isStart: false),
            ]
        }.sorted { $0.date < $1.date }

        var episodes: [Episode] = []
        var previous: Date?
        var awakeCount = 0
        var asleepSamples: [UUID: HealthMeasurement] = [:]
        for boundary in boundaries {
            if let previous, previous < boundary.date, awakeCount == 0, !asleepSamples.isEmpty {
                let duration = boundary.date.timeIntervalSince(previous)
                let zone = timeZoneEvidence(in: asleepSamples.values)
                if let last = episodes.indices.last, previous.timeIntervalSince(episodes[last].end) <= maximumInterruption {
                    episodes[last].end = boundary.date
                    episodes[last].duration += duration
                    episodes[last].zone = zone ?? episodes[last].zone
                } else {
                    episodes.append(Episode(start: previous, end: boundary.date, duration: duration, zone: zone, onsetZone: zone))
                }
            }

            if boundary.asleep {
                asleepSamples[boundary.sample.id] = boundary.isStart ? boundary.sample : nil
            } else {
                awakeCount += boundary.isStart ? 1 : -1
            }
            previous = boundary.date
        }
        return episodes.map {
            SleepEpisode(
                source: source, startDate: $0.start, wakeTime: $0.end, duration: $0.duration,
                timeZoneEvidence: $0.zone ?? .importTimeZone(identifier: fallback.identifier),
                onsetTimeZoneEvidence: $0.onsetZone ?? .importTimeZone(identifier: fallback.identifier)
            )
        }
    }

    private static func timeZoneEvidence(
        in samples: Dictionary<UUID, HealthMeasurement>.Values
    ) -> SleepEpisode.TimeZoneEvidence? {
        let sample = samples.filter { record in
            record.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) != nil
        }.max {
            ($0.endDate, $0.startDate, $0.id.uuidString) < ($1.endDate, $1.startDate, $1.id.uuidString)
        }
        guard let sample, let identifier = sample.timeZoneIdentifier else { return nil }
        return .sampleMetadata(identifier: identifier, sampleID: sample.id)
    }
}
