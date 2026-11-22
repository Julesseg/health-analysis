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
        let app = HealthAnalysisApplication(healthSource: FixtureHealthSource(records: [earlier, latest]))

        await app.healthMeasurements.requestAccessAndRefresh()

        #expect(app.healthMeasurements.readState == .loaded(readableCount: 2))
        #expect(app.healthMeasurements.history == [latest, earlier])
        #expect(app.healthMeasurements.latest == latest)
        #expect(app.overview.hasReadableMeasurements)
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
        #expect(app.healthMeasurements.readState == .loaded(readableCount: 0))
        #expect(app.healthMeasurements.history.isEmpty)
        #expect(app.healthMeasurements.latest == nil)

        await app.healthMeasurements.requestAccessAndRefresh()
        await app.healthMeasurements.requestAccessAndRefresh()

        #expect(app.healthMeasurements.readState == .loaded(readableCount: 0))
        #expect(app.healthMeasurements.history == [record])
        #expect(app.healthMeasurements.latest == record)
    }

    @Test(arguments: [HealthMeasurementReadFailure.protectedData, .read])
    func failedRefreshKeepsPreviouslyImportedHistoryAndFreshness(failure: HealthMeasurementReadFailure) async throws {
        let record = HealthMeasurement(
            id: UUID(),
            metric: .restingHeartRate,
            value: 60,
            unit: .beatsPerMinute,
            startDate: Date(timeIntervalSince1970: 1_763_366_400),
            endDate: Date(timeIntervalSince1970: 1_763_366_400),
            source: .init(name: "Livity", bundleIdentifier: "fixture.livity")
        )
        let source = SequenceHealthSource(reads: [.success([record]), .failure(failure)])
        let app = HealthAnalysisApplication(healthSource: source)
        await app.healthMeasurements.requestAccessAndRefresh()
        let lastSuccess = try #require(app.healthMeasurements.lastSuccessfulReadAt)

        await app.healthMeasurements.refresh()

        #expect(app.healthMeasurements.readState == .failed(failure))
        #expect(app.healthMeasurements.history == [record])
        #expect(app.healthMeasurements.latest == record)
        #expect(app.healthMeasurements.lastSuccessfulReadAt == lastSuccess)
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

        #expect(app.healthMeasurements.readState == .loaded(readableCount: 0))
    }
}

private struct FixtureHealthSource: HealthMeasurementSource {
    let records: [HealthMeasurement]

    func requestReadAccess() async throws {}

    func readMeasurements() async throws -> [HealthMeasurement] {
        records
    }
}

private actor SequenceHealthSource: HealthMeasurementSource {
    private var reads: [Result<[HealthMeasurement], HealthMeasurementReadFailure>]

    init(reads: [Result<[HealthMeasurement], HealthMeasurementReadFailure>]) {
        self.reads = reads
    }

    func requestReadAccess() async throws {}

    func readMeasurements() async throws -> [HealthMeasurement] {
        try reads.removeFirst().get()
    }
}

private struct GatedHealthSource: HealthMeasurementSource {
    let readStarted: AsyncStream<Void>.Continuation
    let results: AsyncStream<[HealthMeasurement]>

    func requestReadAccess() async throws {}

    func readMeasurements() async throws -> [HealthMeasurement] {
        readStarted.yield()
        readStarted.finish()
        var result = results.makeAsyncIterator()
        return await result.next() ?? []
    }
}
