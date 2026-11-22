import Foundation
import HealthAnalysisCore
import Testing

@MainActor
struct SavedAnalysisTests {
    @Test func reopensWholeQuestionsInStablePinOrderAfterEditing() throws {
        let store = TemporaryAnalysisStore()
        let app = store.open()
        let original = AnalysisConfiguration(
            output: .health(metric: .restingHeartRate, sourceBundleIdentifier: "fixture.watch"),
            inputs: [.manualQuantity(UUID()), .manualQuantity(UUID())],
            adjustmentInputs: [.manualQuantity(UUID())],
            behaviorWindow: .precedingDay, history: .fullHistory,
            timeZone: try #require(TimeZone(identifier: "Europe/Paris"))
        )
        var edited = original
        edited.inputs.reverse()
        edited.behaviorWindow = .precedingMonth
        edited.history = .last90Days
        let first = try app.savedAnalyses.save(original)
        let second = try app.savedAnalyses.save(edited)
        let unpinned = try app.savedAnalyses.save(original)
        try app.savedAnalyses.setPinned(true, for: second.id)
        try app.savedAnalyses.setPinned(true, for: first.id)
        try app.savedAnalyses.setPinned(true, for: second.id)
        edited.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))

        let reopened = store.open()
        let updated = try reopened.savedAnalyses.save(edited, updating: second.id)
        let final = store.open()

        #expect(updated.id == second.id)
        #expect(final.savedAnalyses.questions.map(\.id) == [first.id, second.id, unpinned.id])
        #expect(final.savedAnalyses.question(id: first.id)?.configuration == original)
        #expect(final.savedAnalyses.question(id: second.id)?.configuration == edited)
        #expect(final.savedAnalyses.following.map(\.id) == [second.id, first.id])
        #expect(final.overview.hasFollowedAnalyses)
        try final.savedAnalyses.setPinned(false, for: second.id)
        try final.savedAnalyses.setPinned(true, for: second.id)
        #expect(store.open().savedAnalyses.following.map(\.id) == [first.id, second.id])
    }

    @Test func refreshReconcilesCorrectionsDeletionsAndTheCurrentPreferredSource() async throws {
        let store = TemporaryAnalysisStore()
        let fixture = SavedQuestionHistory()
        let watch = fixture.records(source: "fixture.watch", slope: 2)
        let bridge = fixture.records(source: "fixture.bridge", slope: -2)
        let corrected = fixture.measurement(day: 2, value: 62, source: "fixture.bridge")
        let source = SavedQuestionSource(reads: [
            .success(.init(queryID: "restingHeartRate", anchor: Data([1]), added: watch + bridge)),
            .success(.init(queryID: "restingHeartRate", anchor: Data([1]), added: [])),
            .success(.init(
                queryID: "restingHeartRate", anchor: Data([2]),
                added: [corrected], deleted: [bridge[0].id, bridge[1].id]
            ))
        ])
        let app = store.open(source: source)
        let configuration = try fixture.configure(app)
        await app.healthMeasurements.refresh()
        try app.healthMeasurements.setPreferredSource("fixture.watch", for: .restingHeartRate)

        let question = try app.savedAnalyses.save(configuration)
        try app.savedAnalyses.setPinned(true, for: question.id)
        let chosenSource = try #require(app.healthMeasurements.preferredSource(for: .restingHeartRate))
        #expect(chosenSource.bundleIdentifier == "fixture.watch")
        let first = try #require(try await app.refreshAnalysis(configuration)?.get())
        #expect(first.result.estimates.first?.finding == .higher)
        try app.savedAnalyses.save(configuration, updating: question.id, completed: first)

        let reopened = store.open(source: source)
        let cached = try #require(reopened.savedAnalyses.state(for: question.id).completed)
        #expect(cached.result.configuration == configuration)
        #expect(cached.result.estimates.first?.interval == first.result.estimates.first?.interval)
        #expect(cached.result.observations.count == 56)
        #expect(cached.result.observations.first?.inputs.first?.days.count == 1)
        #expect(cached.result.coverage.nonOverlappingWindowCount == 56)
        try reopened.healthMeasurements.setPreferredSource("fixture.bridge", for: .restingHeartRate)

        await reopened.refreshSavedAnalysis(question.id)

        let final = store.open()
        let updated = try #require(final.savedAnalyses.state(for: question.id).completed)
        #expect(updated.updatedAt >= cached.updatedAt)
        #expect(updated.result.outputSource?.bundleIdentifier == "fixture.bridge")
        #expect(updated.result.estimates.first?.finding == .lower)
        #expect(updated.result.coverage.usableDates.count == 55)
        #expect(updated.result.observations.first?.outputValue == 62)
        #expect(final.savedAnalyses.following.map(\.id) == [question.id])

        var edited = configuration
        edited.output = .health(metric: .restingHeartRate, sourceBundleIdentifier: "fixture.watch")
        try final.savedAnalyses.save(edited, updating: question.id, completed: updated)
        let afterEdit = store.open()
        #expect(afterEdit.savedAnalyses.following.first?.configuration == edited)
        #expect(afterEdit.savedAnalyses.state(for: question.id).completed == nil)
    }

    @Test func reopensAdjustedResultWithAllModeledInputs() async throws {
        let store = TemporaryAnalysisStore()
        let fixture = SavedQuestionHistory()
        let sourceID = "fixture.watch"
        let app = store.open(source: SavedQuestionSource(reads: [
            .success(.init(queryID: "restingHeartRate", anchor: Data([1]), added: fixture.records(source: sourceID, slope: 2)))
        ]))
        var configuration = try fixture.configure(app)
        let firstDay = ManualLogDay(fixture.first, timeZone: fixture.timeZone)
        let fluids = try app.manualLog.createQuantity(name: "Fluids", unit: "L", defaultValue: 0, startsOn: firstDay)
        let exercise = try app.manualLog.createQuantity(name: "Exercise", unit: "min", defaultValue: 0, startsOn: firstDay)
        let locale = Locale(identifier: "en_US")
        for index in 0..<56 {
            let day = ManualLogDay(fixture.first.addingTimeInterval(Double(index) * 86_400), timeZone: fixture.timeZone)
            app.manualLog.editQuantity(fluids.id, on: day, text: String(index % 3 + 1), locale: locale)
            app.manualLog.editQuantity(exercise.id, on: day, text: String(index % 11 * 5), locale: locale)
        }
        configuration.inputs.insert(.manualQuantity(fluids.id), at: 0)
        configuration.adjustmentInputs = [.manualQuantity(exercise.id)]
        configuration.output = .health(metric: .restingHeartRate, sourceBundleIdentifier: sourceID)
        let question = try app.savedAnalyses.save(configuration)
        try app.savedAnalyses.setPinned(true, for: question.id)

        await app.refreshSavedAnalysis(question.id)

        let reopened = store.open()
        let result = try #require(reopened.savedAnalyses.state(for: question.id).completed?.result)
        #expect(reopened.savedAnalyses.following.first?.configuration == configuration)
        #expect(result.configuration == configuration)
        #expect(result.model == .numericLinearV1)
        #expect(result.modeledInputs.map(\.name) == ["Fluids", "Caffeine", "Exercise"])
        #expect(result.modeledInputs.map(\.role) == [.input, .input, .adjustment])
        #expect(result.estimates.map(\.input) == configuration.inputs + configuration.adjustmentInputs)
        #expect(result.outputSource?.bundleIdentifier == sourceID)
        let caffeine = try #require(result.estimates.first { $0.input == configuration.inputs[1] })
        #expect(abs(caffeine.difference - 2) < 0.15)
    }

    @Test func overlappingQuestionsWaitForTheReadAndAnEditedQuestionRejectsLateWork() async throws {
        let store = TemporaryAnalysisStore()
        let fixture = SavedQuestionHistory()
        let (reads, readStarted) = AsyncStream<Void>.makeStream()
        let (responses, response) = AsyncStream<Result<HealthMeasurementChanges, HealthMeasurementReadFailure>>.makeStream()
        let source = SuspendedQuestionSource(readStarted: readStarted, responses: responses)
        let app = store.open(source: source)
        let configuration = try fixture.configure(app)
        var otherConfiguration = configuration
        otherConfiguration.output = .health(metric: .restingHeartRate, sourceBundleIdentifier: "fixture.bridge")
        let first = try app.savedAnalyses.save(configuration)
        let second = try app.savedAnalyses.save(otherConfiguration)
        let initial = Task { await app.refreshSavedAnalysis(first.id) }
        var started = reads.makeAsyncIterator()
        await started.next()

        _ = try app.savedAnalyses.save(otherConfiguration, updating: first.id)
        _ = try app.savedAnalyses.save(configuration, updating: first.id)
        #expect(!app.savedAnalyses.state(for: first.id).isRefreshing)

        let (waiting, waiterStarted) = AsyncStream<Void>.makeStream()
        let next = Task {
            waiterStarted.yield()
            waiterStarted.finish()
            await app.refreshSavedAnalysis(second.id)
        }
        var waiter = waiting.makeAsyncIterator()
        await waiter.next()
        #expect(app.savedAnalyses.state(for: second.id).isRefreshing)

        response.yield(.success(.init(
            queryID: "restingHeartRate", anchor: Data([1]), added: fixture.records(source: "fixture.bridge", slope: -2)
        )))
        response.finish()
        await initial.value
        await next.value

        #expect(app.savedAnalyses.state(for: first.id).completed == nil)
        #expect(app.savedAnalyses.state(for: first.id).failure == nil)
        let result = try #require(app.savedAnalyses.state(for: second.id).completed?.result)
        #expect(result.configuration == otherConfiguration)
        #expect(result.estimates.first?.finding == .lower)
        #expect(store.open().savedAnalyses.state(for: first.id).completed == nil)
    }

    @Test func readFailureRetainsTheLastAnswerAndAnEmptySuccessfulRetryReplacesIt() async throws {
        let store = TemporaryAnalysisStore()
        let fixture = SavedQuestionHistory()
        let records = fixture.records(source: "fixture.watch", slope: 2)
        let seed = SavedQuestionSource(reads: [
            .success(.init(queryID: "restingHeartRate", anchor: Data([1]), added: records))
        ])
        let app = store.open(source: seed)
        let configuration = try fixture.configure(app)
        let question = try app.savedAnalyses.save(configuration)
        await app.refreshSavedAnalysis(question.id)
        let prior = try #require(app.savedAnalyses.state(for: question.id).completed)

        let (reads, readStarted) = AsyncStream<Void>.makeStream()
        let (responses, response) = AsyncStream<Result<HealthMeasurementChanges, HealthMeasurementReadFailure>>.makeStream()
        let reopened = store.open(source: SuspendedQuestionSource(readStarted: readStarted, responses: responses))
        let refresh = Task { await reopened.refreshSavedAnalysis(question.id) }
        var started = reads.makeAsyncIterator()
        await started.next()

        #expect(reopened.savedAnalyses.state(for: question.id).isRefreshing)
        #expect(reopened.savedAnalyses.state(for: question.id).completed?.updatedAt == prior.updatedAt)
        response.yield(.failure(.protectedData))
        await refresh.value

        let failedState = reopened.savedAnalyses.state(for: question.id)
        #expect(!failedState.isRefreshing)
        #expect(failedState.failure == .analysis(.healthHistoryUnavailable(.protectedData)))
        #expect(failedState.completed?.updatedAt == prior.updatedAt)
        #expect(failedState.completed?.result.estimates.first?.finding == .higher)
        #expect(store.open().savedAnalyses.state(for: question.id).completed?.updatedAt == prior.updatedAt)

        let neverRun = try reopened.savedAnalyses.save(configuration)
        response.yield(.failure(.protectedData))
        await reopened.refreshSavedAnalysis(neverRun.id)
        #expect(reopened.savedAnalyses.state(for: neverRun.id).failure == .analysis(.healthHistoryUnavailable(.protectedData)))
        #expect(reopened.savedAnalyses.state(for: neverRun.id).completed == nil)

        response.yield(.success(.init(
            queryID: "restingHeartRate", anchor: Data([2]), added: [], deleted: records.map(\.id)
        )))
        response.finish()
        await reopened.refreshSavedAnalysis(question.id)
        let retried = try #require(reopened.savedAnalyses.state(for: question.id).completed)
        #expect(reopened.savedAnalyses.state(for: question.id).failure == nil)
        #expect(retried.updatedAt > prior.updatedAt)
        #expect(retried.result.estimates.isEmpty)
        #expect(retried.result.coverage.usableDates.isEmpty)
        #expect(retried.result.evidence.grade == .insufficient)
        #expect(store.open().savedAnalyses.state(for: question.id).completed?.updatedAt == retried.updatedAt)
    }

    @Test func failedCacheWriteKeepsTheLastSuccessfulAnalysisAvailable() async throws {
        let store = TemporaryAnalysisStore()
        let fixture = SavedQuestionHistory()
        let records = fixture.records(source: "fixture.watch", slope: 2)
        let app = store.open(source: SavedQuestionSource(reads: [
            .success(.init(queryID: "restingHeartRate", anchor: Data([1]), added: records)),
            .success(.init(queryID: "restingHeartRate", anchor: Data([2]), added: [], deleted: records.map(\.id)))
        ]))
        let question = try app.savedAnalyses.save(fixture.configure(app))
        await app.refreshSavedAnalysis(question.id)
        let prior = try #require(app.savedAnalyses.state(for: question.id).completed)
        let backupURL = store.directory.appending(path: "backup.json")
        let files = FileManager.default
        try files.moveItem(at: store.savedAnalysesURL, to: backupURL)
        try files.createDirectory(at: store.savedAnalysesURL, withIntermediateDirectories: false)

        await app.refreshSavedAnalysis(question.id)

        let failed = app.savedAnalyses.state(for: question.id)
        #expect(failed.failure == .persistence)
        #expect(failed.completed?.updatedAt == prior.updatedAt)
        #expect(failed.completed?.result.estimates.first?.finding == .higher)
        try files.removeItem(at: store.savedAnalysesURL)
        try files.moveItem(at: backupURL, to: store.savedAnalysesURL)
        #expect(store.open().savedAnalyses.state(for: question.id).completed?.updatedAt == prior.updatedAt)
    }
}

private final class TemporaryAnalysisStore {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    var savedAnalysesURL: URL { directory.appending(path: "analyses.json") }

    func open(source: (any HealthMeasurementSource)? = nil) -> HealthAnalysisApplication {
        HealthAnalysisApplication(
            healthSource: source,
            healthHistoryStoreURL: directory.appending(path: "health.json"),
            manualLogStoreURL: directory.appending(path: "log.json"),
            savedAnalysesStoreURL: savedAnalysesURL
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct SavedQuestionHistory {
    let first = Date(timeIntervalSince1970: 1_735_689_600)
    let timeZone = TimeZone(secondsFromGMT: 0)!

    @MainActor func configure(_ app: HealthAnalysisApplication) throws -> AnalysisConfiguration {
        let caffeine = try app.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 0,
            startsOn: ManualLogDay(first, timeZone: timeZone)
        )
        for index in 0..<56 {
            let date = first.addingTimeInterval(Double(index) * 86_400)
            let day = ManualLogDay(date, timeZone: timeZone)
            app.manualLog.editQuantity(caffeine.id, on: day, text: String(amount(index)), locale: Locale(identifier: "en_US"))
        }
        return .init(output: .health(metric: .restingHeartRate), inputs: [.manualQuantity(caffeine.id)], timeZone: timeZone)
    }

    func records(source: String, slope: Double) -> [HealthMeasurement] {
        (0..<56).map { index in
            let bpm = 65 + slope * Double(amount(index)) / 100 + Double(index % 7 - 3) * 0.17
            return measurement(day: index + 1, value: bpm, source: source)
        }
    }

    func measurement(day: Int, value: Double, source: String) -> HealthMeasurement {
        let date = first.addingTimeInterval(Double(day * 86_400 + 32_400))
        return .init(
            id: UUID(), metric: .restingHeartRate, value: value, unit: .beatsPerMinute,
            startDate: date, endDate: date, source: .init(name: source, bundleIdentifier: source)
        )
    }

    private func amount(_ index: Int) -> Int { 50 + index % 5 * 50 }
}

private actor SavedQuestionSource: HealthMeasurementSource {
    private var reads: [Result<HealthMeasurementChanges, HealthMeasurementReadFailure>]

    init(reads: [Result<HealthMeasurementChanges, HealthMeasurementReadFailure>]) {
        self.reads = reads
    }

    func requestReadAccess() async throws {}

    func readChanges(
        after anchors: [String: Data], includingPreviouslySaved: Bool
    ) async throws -> [HealthMeasurementChanges] {
        [try reads.removeFirst().get()]
    }
}

private struct SuspendedQuestionSource: HealthMeasurementSource {
    let readStarted: AsyncStream<Void>.Continuation
    let responses: AsyncStream<Result<HealthMeasurementChanges, HealthMeasurementReadFailure>>

    func requestReadAccess() async throws {}

    func readChanges(
        after anchors: [String: Data], includingPreviouslySaved: Bool
    ) async throws -> [HealthMeasurementChanges] {
        readStarted.yield()
        readStarted.finish()
        var results = responses.makeAsyncIterator()
        guard let result = await results.next() else { throw HealthMeasurementReadFailure.read }
        return [try result.get()]
    }
}
