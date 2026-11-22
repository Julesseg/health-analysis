import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct HealthMeasurementImportTests {
    @Test func importExposesHistoryAndLatestMeasurementWithProvenance() async throws {
        let earlier = HealthMeasurement(
            id: UUID(uuidString: "E05E700F-7CBD-4257-B11A-6C2CBD3ACA3D")!,
            metric: .restingHeartRate,
            value: 57,
            unit: .beatsPerMinute,
            startDate: Date(timeIntervalSince1970: 1_763_193_600),
            endDate: Date(timeIntervalSince1970: 1_763_197_200),
            source: .init(name: "Livity", bundleIdentifier: "fixture.livity")
        )
        let latest = HealthMeasurement(
            id: UUID(uuidString: "D3EC7C08-C237-45F1-B7AE-59DFD2F2ACD1")!,
            metric: .restingHeartRate,
            value: 61.5,
            unit: .beatsPerMinute,
            startDate: Date(timeIntervalSince1970: 1_763_366_400),
            endDate: Date(timeIntervalSince1970: 1_763_366_400),
            source: .init(name: "Apple Watch", bundleIdentifier: "fixture.watch")
        )
        let store = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: store) }
        let url = store.appending(path: "history.json")
        let app = HealthAnalysisApplication(
            healthSource: FixtureHealthSource(records: [earlier, latest]),
            healthHistoryStoreURL: url
        )

        await app.healthMeasurements.requestAccessAndRefresh()

        #expect(app.healthMeasurements.readState == .loaded)
        #expect(app.healthMeasurements.history == [latest, earlier])
        #expect(app.healthMeasurements.latest == latest)
        #expect(app.overview.hasReadableMeasurements)

        let reopened = HealthAnalysisApplication(healthHistoryStoreURL: url)
        #expect(reopened.healthMeasurements.history == [latest, earlier])
        #expect(reopened.healthMeasurements.lastSuccessfulReadAt == app.healthMeasurements.lastSuccessfulReadAt)
    }

    @Test func emptyReadsReportNoReadableMeasurementsAndKeepEarlierRecords() async {
        let record = HealthMeasurement(
            id: UUID(),
            metric: .restingHeartRate,
            value: 60,
            unit: .beatsPerMinute,
            startDate: Date(timeIntervalSince1970: 1_763_366_400),
            endDate: Date(timeIntervalSince1970: 1_763_366_400),
            source: .init(name: "Livity", bundleIdentifier: "fixture.livity")
        )
        let source = SequenceHealthSource(reads: [.success([]), .success([record]), .success([])])
        let app = HealthAnalysisApplication(healthSource: source)

        await app.healthMeasurements.requestAccessAndRefresh()
        #expect(app.healthMeasurements.readState == .loaded)
        #expect(app.healthMeasurements.history.isEmpty)
        #expect(app.healthMeasurements.latest == nil)

        await app.healthMeasurements.requestAccessAndRefresh()
        await app.healthMeasurements.requestAccessAndRefresh()

        #expect(app.healthMeasurements.readState == .loaded)
        #expect(app.healthMeasurements.history == [record])
        #expect(app.healthMeasurements.latest == record)
    }

    @Test func overlappingQueriesReconcileCorrectionsAndDeletionsAcrossReopens() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.json")
        let old = measurement(value: 64)
        let corrected = measurement(value: 61)
        let unchanged = measurement(value: 56, daysLater: 1)
        let firstAnchor = Data([1])
        let overlapAnchor = Data([20])
        let nextAnchor = Data([2])

        let initialSource = AnchoredFixtureSource { anchors in
            guard anchors.isEmpty else { throw HealthMeasurementReadFailure.read }
            return [
                .init(queryID: "full", anchor: firstAnchor, added: [old, unchanged]),
                .init(queryID: "overlap", anchor: overlapAnchor, added: [old]),
            ]
        }
        let initial = HealthAnalysisApplication(healthSource: initialSource, healthHistoryStoreURL: url)
        await initial.healthMeasurements.refresh()
        #expect(initial.healthMeasurements.history == [unchanged, old])

        let correctionSource = AnchoredFixtureSource { anchors in
            guard anchors == ["full": firstAnchor, "overlap": overlapAnchor] else {
                throw HealthMeasurementReadFailure.read
            }
            return [
                .init(queryID: "full", anchor: nextAnchor, added: [corrected], deleted: [old.id]),
                .init(queryID: "overlap", anchor: overlapAnchor, added: [unchanged, old]),
            ]
        }
        let updated = HealthAnalysisApplication(healthSource: correctionSource, healthHistoryStoreURL: url)
        await updated.healthMeasurements.refresh()
        #expect(updated.healthMeasurements.history == [unchanged, corrected])

        let replaySource = AnchoredFixtureSource { anchors in
            guard anchors == ["full": nextAnchor, "overlap": overlapAnchor] else {
                throw HealthMeasurementReadFailure.read
            }
            return [
                .init(queryID: "overlap", anchor: overlapAnchor, added: [old, unchanged, corrected]),
            ]
        }
        let reopened = HealthAnalysisApplication(healthSource: replaySource, healthHistoryStoreURL: url)
        #expect(reopened.healthMeasurements.history == [unchanged, corrected])
        await reopened.healthMeasurements.refresh()
        #expect(reopened.healthMeasurements.history == [unchanged, corrected])
    }

    @Test func preferredSourceAndItsCoverageSurviveReopenWithoutCombiningDefinitions() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.json")
        let incompatible = HealthMeasurement.Metric(rawValue: "fixture.incompatible-definition")
        let livity = HealthMeasurement.Source(name: "Livity", bundleIdentifier: "fixture.livity")
        let watch = HealthMeasurement.Source(name: "Apple Watch", bundleIdentifier: "fixture.watch")
        let first = measurement(value: 58, source: livity)
        let last = measurement(value: 60, daysLater: 3, source: livity)
        let overlapping = measurement(value: 62, daysLater: 3, source: watch)
        let different = measurement(value: 71, daysLater: 6, metric: incompatible, source: livity)
        let source = FixtureHealthSource(records: [first, last, overlapping, different])
        let app = HealthAnalysisApplication(healthSource: source, healthHistoryStoreURL: url)
        await app.healthMeasurements.requestAccessAndRefresh()
        let lastCheck = try #require(app.healthMeasurements.lastSuccessfulReadAt)
        #expect(Set(app.healthMeasurements.sources(for: .restingHeartRate).map(\.bundleIdentifier)) ==
            [watch.bundleIdentifier, livity.bundleIdentifier])

        try app.healthMeasurements.setPreferredSource(livity.bundleIdentifier, for: .restingHeartRate)
        let reopened = HealthAnalysisApplication(healthHistoryStoreURL: url)
        let history = reopened.healthMeasurements
        #expect(history.preferredSource(for: .restingHeartRate) == livity)
        #expect(history.preferredSource(for: incompatible) == nil)
        #expect(history.measurements(for: .restingHeartRate) == [last, first])
        #expect(history.measurements(for: incompatible) == [different])
        #expect(history.latest == last)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let coverage = try #require(history.coverage(for: .restingHeartRate, calendar: calendar))
        #expect(coverage.firstMeasurement == first.startDate)
        #expect(coverage.latestMeasurement == last.startDate)
        #expect(coverage.measuredDays == 2)
        #expect(coverage.daysWithoutMeasurements == 2)
        #expect(history.lastSuccessfulReadAt == lastCheck)

        try history.setPreferredSource(watch.bundleIdentifier, for: .restingHeartRate)
        let deletionSource = AnchoredFixtureSource { _ in
            [.init(queryID: "full", anchor: Data([2]), added: [], deleted: [overlapping.id])]
        }
        let switched = HealthAnalysisApplication(healthSource: deletionSource, healthHistoryStoreURL: url).healthMeasurements
        #expect(switched.latest == overlapping)
        #expect(switched.coverage(for: .restingHeartRate, calendar: calendar)?.daysWithoutMeasurements == 0)
        #expect(switched.lastSuccessfulReadAt == lastCheck)

        await switched.refresh()
        let afterDeletion = HealthAnalysisApplication(healthHistoryStoreURL: url).healthMeasurements
        #expect(afterDeletion.preferredSource(for: .restingHeartRate) == watch)
        #expect(afterDeletion.latest == nil)
        #expect(afterDeletion.coverage(for: .restingHeartRate, calendar: calendar) == nil)
        try afterDeletion.setPreferredSource(nil, for: .restingHeartRate)
        #expect(afterDeletion.measurements(for: .restingHeartRate) == [last, first])
    }

    private func measurement(
        value: Double,
        daysLater: Int = 0,
        metric: HealthMeasurement.Metric = .restingHeartRate,
        source: HealthMeasurement.Source = .init(name: "Livity", bundleIdentifier: "fixture.livity")
    ) -> HealthMeasurement {
        let date = Date(timeIntervalSince1970: 1_763_366_400 + Double(daysLater) * 86_400)
        return HealthMeasurement(
            id: UUID(),
            metric: metric,
            value: value,
            unit: .beatsPerMinute,
            startDate: date,
            endDate: date,
            source: source
        )
    }

    @Test(arguments: [HealthMeasurementReadFailure.protectedData, .read])
    func failedRefreshKeepsPreviouslyImportedHistoryAndFreshness(failure: HealthMeasurementReadFailure) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.json")
        let record = measurement(value: 60)
        let source = SequenceHealthSource(reads: [.success([record]), .failure(failure)])
        let app = HealthAnalysisApplication(healthSource: source, healthHistoryStoreURL: url)
        await app.healthMeasurements.requestAccessAndRefresh()
        let lastSuccess = try #require(app.healthMeasurements.lastSuccessfulReadAt)

        await app.healthMeasurements.refresh()

        #expect(app.healthMeasurements.readState == .failed(failure))
        #expect(app.healthMeasurements.history == [record])
        #expect(app.healthMeasurements.latest == record)
        #expect(app.healthMeasurements.lastSuccessfulReadAt == lastSuccess)

        let reopened = HealthAnalysisApplication(healthHistoryStoreURL: url)
        #expect(reopened.healthMeasurements.history == [record])
        #expect(reopened.healthMeasurements.lastSuccessfulReadAt == lastSuccess)
    }

    @Test func failedPersistenceLeavesChangesAndTheirAnchorAvailableForRetry() async throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? files.removeItem(at: directory) }
        let store = directory.appending(path: "store")
        let movedStore = directory.appending(path: "moved")
        let url = store.appending(path: "history.json")
        let old = measurement(value: 58)
        let replacement = measurement(value: 60)
        let initialAnchor = Data([1])
        let nextAnchor = Data([2])
        let source = AnchoredFixtureSource { anchors in
            switch anchors["full"] {
            case nil:
                [.init(queryID: "full", anchor: initialAnchor, added: [old])]
            case initialAnchor:
                [.init(queryID: "full", anchor: nextAnchor, added: [replacement], deleted: [old.id])]
            default:
                throw HealthMeasurementReadFailure.read
            }
        }
        let app = HealthAnalysisApplication(healthSource: source, healthHistoryStoreURL: url)
        let history = app.healthMeasurements
        await history.refresh()
        let lastCheck = try #require(history.lastSuccessfulReadAt)

        try files.moveItem(at: store, to: movedStore)
        try Data().write(to: store)
        await history.refresh()
        #expect(history.readState == .failed(.persistence))
        #expect(history.history == [old])
        #expect(history.lastSuccessfulReadAt == lastCheck)

        try files.removeItem(at: store)
        try files.moveItem(at: movedStore, to: store)
        let beforeRetry = HealthAnalysisApplication(healthHistoryStoreURL: url).healthMeasurements
        #expect(beforeRetry.history == [old])
        #expect(beforeRetry.lastSuccessfulReadAt == lastCheck)

        await history.refresh()
        #expect(history.readState == .loaded)
        #expect(history.history == [replacement])
        let afterRetry = HealthAnalysisApplication(healthHistoryStoreURL: url).healthMeasurements
        #expect(afterRetry.history == [replacement])
        #expect(afterRetry.lastSuccessfulReadAt == history.lastSuccessfulReadAt)
    }

    @Test func loadingIsObservableBeforeTheFirstReadCompletes() async {
        let (readsStarted, readStarted) = AsyncStream<Void>.makeStream()
        let (results, result) = AsyncStream<[HealthMeasurement]>.makeStream()
        let app = HealthAnalysisApplication(healthSource: GatedHealthSource(
            readStarted: readStarted,
            results: results
        ))
        let importTask = Task { await app.healthMeasurements.requestAccessAndRefresh() }
        var started = readsStarted.makeAsyncIterator()
        await started.next()

        #expect(app.healthMeasurements.readState == .loading)
        #expect(app.healthMeasurements.lastSuccessfulReadAt == nil)

        result.yield([])
        result.finish()
        await importTask.value

        #expect(app.healthMeasurements.readState == .loaded)
    }
}

private struct AnchoredFixtureSource: HealthMeasurementSource {
    let update: @Sendable ([String: Data]) throws -> [HealthMeasurementChanges]

    func requestReadAccess() async throws {}

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        try update(anchors)
    }
}

private struct FixtureHealthSource: HealthMeasurementSource {
    let records: [HealthMeasurement]

    func requestReadAccess() async throws {}

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        [.init(queryID: "full", anchor: Data([1]), added: records)]
    }
}

private actor SequenceHealthSource: HealthMeasurementSource {
    private var reads: [Result<[HealthMeasurement], HealthMeasurementReadFailure>]

    init(reads: [Result<[HealthMeasurement], HealthMeasurementReadFailure>]) {
        self.reads = reads
    }

    func requestReadAccess() async throws {}

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        [.init(queryID: "full", anchor: Data([1]), added: try reads.removeFirst().get())]
    }
}

private struct GatedHealthSource: HealthMeasurementSource {
    let readStarted: AsyncStream<Void>.Continuation
    let results: AsyncStream<[HealthMeasurement]>

    func requestReadAccess() async throws {}

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        readStarted.yield()
        readStarted.finish()
        var result = results.makeAsyncIterator()
        return [.init(queryID: "full", anchor: Data([1]), added: await result.next() ?? [])]
    }
}
