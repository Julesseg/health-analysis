import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct HRVImportTests {
    @Test func storedHRVTypesAndSavingSourcesHaveSeparateHistoryAndCoverage() async throws {
        let bridge = HealthMeasurement.Source(name: "Livity", bundleIdentifier: "fixture.bridge")
        let watch = HealthMeasurement.Source(name: "Watch", bundleIdentifier: "fixture.watch")
        let first = hrv(id: 1, type: .sdnn, day: 0, source: bridge)
        let latest = hrv(id: 2, type: .sdnn, day: 2, source: bridge)
        let overlapping = hrv(id: 3, type: .sdnn, day: 2, source: watch)
        let differentMeasure = hrv(id: 4, type: .rmssd, day: 1, source: bridge)
        let restingHeartRate = HealthMeasurement(
            id: UUID(uuidString: "0C4B09FD-CAC3-4709-8B47-000000000005")!,
            metric: .restingHeartRate, value: 58, unit: .beatsPerMinute,
            startDate: first.startDate, endDate: first.startDate, source: watch
        )
        let app = HealthAnalysisApplication(healthSource: FixtureSource { _ in
            [
                .init(queryID: "sdnn", anchor: Data([1]), added: [first, latest, overlapping]),
                .init(queryID: "rmssd", anchor: Data([2]), added: [differentMeasure]),
                .init(queryID: "restingHeartRate", anchor: Data([3]), added: [restingHeartRate]),
            ]
        })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        await app.healthMeasurements.refresh()

        let sdnn = app.healthMeasurements.hrvSeries(for: .sdnn, calendar: calendar)
        let rmssd = app.healthMeasurements.hrvSeries(for: .rmssd, calendar: calendar)
        #expect(sdnn.count == 2)
        #expect(rmssd.count == 1)
        let bridgeSDNN = try #require(sdnn.first { $0.source == bridge })
        let watchSDNN = try #require(sdnn.first { $0.source == watch })
        let bridgeRMSSD = try #require(rmssd.first { $0.source == bridge })
        #expect(bridgeSDNN.records == [latest, first])
        #expect(watchSDNN.records == [overlapping])
        #expect(bridgeRMSSD.records == [differentMeasure])
        #expect(bridgeSDNN.coverage.recordCount == 2)
        #expect(bridgeSDNN.coverage.firstMeasurement == first.startDate)
        #expect(bridgeSDNN.coverage.latestMeasurement == latest.startDate)
        #expect(bridgeSDNN.coverage.measuredDays == 2)
        #expect(bridgeSDNN.coverage.daysWithoutMeasurements == 1)
        #expect(bridgeRMSSD.coverage.daysWithoutMeasurements == 0)
        #expect(bridgeSDNN.analysisLimitation == .unverifiedOriginalMeasureAndSummary)
        #expect(bridgeRMSSD.analysisLimitation == .unverifiedOriginalMeasureAndSummary)
        #expect(app.healthMeasurements.latest == restingHeartRate)
    }

    @Test func hrvInspectionPreservesEvidenceThroughReplayCorrectionAndReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.json")
        let bridge = HealthMeasurement.Source(name: "Livity", bundleIdentifier: "fixture.bridge")
        let original = hrv(
            id: 1, type: .sdnn, day: 0, source: bridge,
            revision: .init(version: "1.0", productType: "iPhoneFixture", operatingSystemVersion: "27.0.0"),
            provenance: .init(quantityCount: 1, syncIdentifier: "night-1", syncVersion: 1)
        )
        let replacement = hrv(
            id: 2, type: .sdnn, day: 0, source: bridge,
            revision: .init(version: "1.1", productType: "iPhoneFixture", operatingSystemVersion: "27.1.0"),
            provenance: .init(quantityCount: 1, syncIdentifier: "night-1", syncVersion: 2)
        )
        let sameTime = hrv(id: 3, type: .sdnn, day: 0, source: bridge)
        let source = FixtureSource { anchors in
            if anchors.isEmpty {
                return [.init(queryID: "sdnn", anchor: Data([1]), added: [original, sameTime, original])]
            }
            return [.init(queryID: "sdnn", anchor: Data([2]), added: [original, replacement], deleted: [original.id])]
        }
        let app = HealthAnalysisApplication(healthSource: source, healthHistoryStoreURL: url)
        await app.healthMeasurements.refresh()
        let initial = try #require(app.healthMeasurements.hrvSeries(for: .sdnn).first)
        #expect(initial.records == [original, sameTime])

        await app.healthMeasurements.refresh()

        let reopened = HealthAnalysisApplication(healthHistoryStoreURL: url)
        let corrected = try #require(reopened.healthMeasurements.hrvSeries(for: .sdnn).first)
        #expect(corrected.records == [replacement, sameTime])
        #expect(corrected.records.first?.sourceRevision?.version == "1.1")
        #expect(corrected.records.first?.hrvProvenance?.syncVersion == 2)
        #expect(corrected.analysisLimitation == .unverifiedOriginalMeasureAndSummary)
    }

    private func hrv(
        id: Int, type: HRVSeries.StoredType, day: Int, source: HealthMeasurement.Source,
        revision: HealthMeasurement.SourceRevision? = nil,
        provenance: HealthMeasurement.HRVProvenance? = nil
    ) -> HealthMeasurement {
        let start = Date(timeIntervalSince1970: 1_763_366_400 + Double(day) * 86_400)
        return HealthMeasurement(
            id: UUID(uuidString: "0C4B09FD-CAC3-4709-8B47-00000000000\(id)")!,
            metric: type.metric,
            value: 42,
            unit: .milliseconds,
            startDate: start,
            endDate: start.addingTimeInterval(300),
            source: source,
            timeZoneIdentifier: "Europe/Paris",
            sourceRevision: revision,
            hrvProvenance: provenance
        )
    }
}

private struct FixtureSource: HealthMeasurementSource {
    let update: @Sendable ([String: Data]) throws -> [HealthMeasurementChanges]

    func requestReadAccess() async throws {}

    func readChanges(
        after anchors: [String: Data], includingPreviouslySaved: Bool
    ) async throws -> [HealthMeasurementChanges] {
        try update(anchors)
    }
}
