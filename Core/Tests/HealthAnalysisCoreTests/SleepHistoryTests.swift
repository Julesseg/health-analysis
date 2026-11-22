import Foundation
import Testing
import HealthAnalysisCore

@MainActor
struct SleepHistoryTests {
    @Test func overlappingStagesProduceElapsedSleepAndWakeTimingAcrossDaylightSaving() async throws {
        let watch = HealthMeasurement.Source(name: "Watch", bundleIdentifier: "fixture.watch")
        let inBed = stage(.inBed, "2026-03-28T21:00:00Z", "2026-03-29T07:00:00Z", source: watch)
        let unspecified = stage(.asleepUnspecified, "2026-03-28T22:30:00Z", "2026-03-29T05:30:00Z", source: watch)
        let core = stage(.asleepCore, "2026-03-29T00:00:00Z", "2026-03-29T02:30:00Z", source: watch)
        let awake = stage(.awake, "2026-03-29T01:15:00Z", "2026-03-29T01:45:00Z", source: watch)
        let rem = stage(.asleepREM, "2026-03-29T05:15:00Z", "2026-03-29T06:00:00Z", source: watch)
        let app = HealthAnalysisApplication(healthSource: SleepFixtureSource { _ in
            .init(queryID: "sleep", anchor: Data([1]), added: [inBed, unspecified, core, awake, rem, rem])
        })

        await app.healthMeasurements.requestAccessAndRefresh()

        let episode = try #require(app.healthMeasurements.sleepEpisodes.first)
        #expect(app.healthMeasurements.sleepEpisodes.count == 1)
        #expect(episode.duration == 25_200)
        #expect(episode.startDate == date("2026-03-28T22:30:00Z"))
        #expect(episode.wakeTime == date("2026-03-29T06:00:00Z"))
        #expect(episode.wakeDay == DateComponents(year: 2026, month: 3, day: 29))
        #expect(episode.timeZoneEvidence == .sampleMetadata(identifier: "Europe/Paris", sampleID: rem.id))
        #expect(episode.source == watch)
        #expect(Set(app.healthMeasurements.history.map(\.id)) == [inBed.id, unspecified.id, core.id, awake.id, rem.id])
    }

    @Test func preferredSleepHistoryUsesLocalWakeDaysAndRebuildsAfterStageCorrection() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appending(path: "measurements.json")
        let watch = HealthMeasurement.Source(name: "Watch", bundleIdentifier: "fixture.watch")
        let bridge = HealthMeasurement.Source(name: "Bridge", bundleIdentifier: "fixture.bridge")
        let first = stage(.asleepCore, "2026-03-28T12:00:00Z", "2026-03-28T21:00:00Z", source: watch, timeZone: "Asia/Tokyo")
        let alternative = stage(.asleepUnspecified, "2026-03-28T13:00:00Z", "2026-03-28T20:00:00Z", source: bridge, timeZone: "America/Los_Angeles")
        let second = stage(.asleepCore, "2026-03-30T13:00:00Z", "2026-03-30T18:00:00Z", source: watch, timeZone: "Asia/Tokyo")
        let originalEnd = stage(.asleepDeep, "2026-03-30T18:00:00Z", "2026-03-30T21:00:00Z", source: watch, timeZone: "Asia/Tokyo")
        let correctedEnd = stage(.asleepDeep, "2026-03-30T18:00:00Z", "2026-03-30T20:00:00Z", source: watch, timeZone: "Asia/Tokyo")
        let source = SleepFixtureSource { anchors in
            switch anchors["sleep"] {
            case nil:
                .init(queryID: "sleep", anchor: Data([1]), added: [first, alternative, second, originalEnd])
            case Data([1]):
                .init(queryID: "sleep", anchor: Data([2]), added: [correctedEnd], deleted: [originalEnd.id])
            case Data([2]):
                .init(queryID: "sleep", anchor: Data([2]), added: [originalEnd, second, correctedEnd])
            default:
                throw HealthMeasurementReadFailure.read
            }
        }
        let history = HealthAnalysisApplication(healthSource: source, healthHistoryStoreURL: store).healthMeasurements
        await history.refresh()
        #expect(history.sleepEpisodes.map(\.duration) == [28_800, 32_400, 25_200])
        #expect(history.sleepEpisodes.map { $0.wakeDay.day } == [31, 29, 28])
        try history.setPreferredSource(watch.bundleIdentifier, for: .sleepAnalysis)

        let updated = HealthAnalysisApplication(healthSource: source, healthHistoryStoreURL: store).healthMeasurements
        await updated.refresh()
        #expect(updated.sleepEpisodes.map(\.duration) == [25_200, 32_400])
        #expect(updated.sleepEpisodes.first?.wakeTime == date("2026-03-30T20:00:00Z"))
        #expect(updated.sleepEpisodes.first?.wakeDay == DateComponents(year: 2026, month: 3, day: 31))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let coverage = try #require(updated.coverage(for: .sleepAnalysis, calendar: calendar))
        #expect(coverage.recordCount == 2)
        #expect(coverage.firstMeasurement == first.endDate)
        #expect(coverage.latestMeasurement == correctedEnd.endDate)
        #expect(coverage.latestMeasurementTimeZone?.identifier == "Asia/Tokyo")
        #expect(coverage.measuredDays == 2)
        #expect(coverage.daysWithoutMeasurements == 1)

        let reopened = HealthAnalysisApplication(healthSource: source, healthHistoryStoreURL: store).healthMeasurements
        await reopened.refresh()
        #expect(reopened.sleepEpisodes == updated.sleepEpisodes)
        #expect(Set(reopened.history.map(\.id)) == [first.id, alternative.id, second.id, correctedEnd.id])
        #expect(reopened.history.contains(correctedEnd))
    }

    @Test func stageOnlyHistoryHasNoCoverageAndLongAwakeIntervalsSeparateEpisodes() async throws {
        let watch = HealthMeasurement.Source(name: "Watch", bundleIdentifier: "fixture.watch")
        let bed = stage(.inBed, "2026-11-09T21:00:00Z", "2026-11-10T08:00:00Z", source: watch)
        let awake = stage(.awake, "2026-11-10T00:00:00Z", "2026-11-10T02:00:00Z", source: watch)
        let unknown = stage(.init(rawValue: 99), "2026-11-09T21:00:00Z", "2026-11-10T08:00:00Z", source: watch)
        let sleep = stage(.asleepUnspecified, "2026-11-09T22:00:00Z", "2026-11-10T04:00:00Z", source: watch, timeZone: "Invalid zone")
        let source = SleepFixtureSource { anchors in
            if anchors["sleep"] == nil {
                return .init(queryID: "sleep", anchor: Data([1]), added: [bed, awake, unknown])
            }
            return .init(queryID: "sleep", anchor: Data([2]), added: [sleep])
        }
        let history = HealthAnalysisApplication(healthSource: source).healthMeasurements
        await history.refresh()
        #expect(history.sources(for: .sleepAnalysis) == [watch])
        #expect(history.sleepEpisodes.isEmpty)
        #expect(history.coverage(for: .sleepAnalysis) == nil)

        await history.refresh()
        #expect(history.sleepEpisodes.map(\.duration) == [7_200, 7_200])
        #expect(history.sleepEpisodes.map(\.wakeTime) == [
            date("2026-11-10T04:00:00Z"),
            date("2026-11-10T00:00:00Z"),
        ])
        #expect(history.sleepEpisodes.allSatisfy { $0.timeZoneEvidence == .importTimeZone(identifier: TimeZone.current.identifier) })
        #expect(history.history.first(where: { $0.id == sleep.id })?.timeZoneIdentifier == "Invalid zone")
        #expect(history.history.first(where: { $0.id == unknown.id })?.sleepStage?.rawValue == 99)
    }

    private func stage(
        _ stage: SleepStage,
        _ start: String,
        _ end: String,
        source: HealthMeasurement.Source,
        timeZone: String? = "Europe/Paris"
    ) -> HealthMeasurement {
        HealthMeasurement(
            id: UUID(),
            sleepStage: stage,
            startDate: date(start),
            endDate: date(end),
            source: source,
            timeZoneIdentifier: timeZone,
            sourceRevision: .init(version: "1.0", productType: "Watch", operatingSystemVersion: "27.0.0")
        )
    }

    private func date(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }
}

private struct SleepFixtureSource: HealthMeasurementSource {
    let update: @Sendable ([String: Data]) throws -> HealthMeasurementChanges

    func requestReadAccess() async throws {}

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        [try update(anchors)]
    }
}
