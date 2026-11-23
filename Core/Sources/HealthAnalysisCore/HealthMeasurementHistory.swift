import Foundation
import Observation

@MainActor
@Observable
public final class HealthMeasurementHistory {
    public enum ReadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(HealthMeasurementReadFailure)
    }

    public enum PreferenceFailure: Error {
        case unknownSource
        case persistence
    }

    public struct Coverage: Sendable {
        public let recordCount: Int
        public let firstMeasurement: Date
        public let latestMeasurement: Date
        public let firstMeasurementTimeZone: TimeZone?
        public let latestMeasurementTimeZone: TimeZone?
        public let measuredDays: Int
        public let daysWithoutMeasurements: Int
    }

    private struct Snapshot: Codable, Sendable {
        var records: [HealthMeasurement] = []
        var anchors: [String: Data] = [:]
        var deletedRecordIDs: Set<UUID> = []
        var preferredSources: [String: HealthMeasurement.Source] = [:]
        var lastSuccessfulReadAt: Date?
        var sleepFallbackTimeZoneIdentifier: String?
        var workouts: [HealthWorkout]?
        var analysisChanges: [AnalysisSeriesID: Date]?

        static func load(from url: URL) throws -> Self {
            do {
                return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return Self()
            }
        }
    }

    public private(set) var readState: ReadState = .idle
    public private(set) var reconciliationVersion = 0
    public var history: [HealthMeasurement] { snapshot?.records ?? [] }
    public var workouts: [HealthWorkout] { snapshot?.workouts ?? [] }
    public var hasReadableRecords: Bool { !history.isEmpty || !workouts.isEmpty }
    public var lastSuccessfulReadAt: Date? { snapshot?.lastSuccessfulReadAt }
    public var latest: HealthMeasurement? { measurements(for: .restingHeartRate).first }
    public var sleepEpisodes: [SleepEpisode] {
        deriveSleepEpisodes(from: measurements(for: .sleepAnalysis))
    }

    func deriveSleepEpisodes(from records: [HealthMeasurement]) -> [SleepEpisode] {
        let fallback = snapshot?.sleepFallbackTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        return SleepDerivation.episodes(from: records, fallback: fallback)
    }

    private let source: (any HealthMeasurementSource)?
    private let storeURL: URL?
    private var snapshot: Snapshot?
    @ObservationIgnored private var analysisReadWaiters: [CheckedContinuation<ReadState?, Never>] = []

    nonisolated init(source: (any HealthMeasurementSource)?, storeURL: URL?) {
        self.source = source
        self.storeURL = storeURL
        let stored = try? storeURL.map(Snapshot.load(from:)) ?? Snapshot()
        _snapshot = stored
        if stored == nil {
            _readState = .failed(.persistence)
        } else if stored?.lastSuccessfulReadAt != nil {
            _readState = .loaded
        }
    }

    public func preferredSource(for metric: HealthMeasurement.Metric) -> HealthMeasurement.Source? {
        snapshot?.preferredSources[metric.rawValue]
    }

    func analysisChangeDate(for series: AnalysisSeriesID) -> Date? {
        guard let snapshot else { return nil }
        guard let analysisChanges = snapshot.analysisChanges else { return snapshot.lastSuccessfulReadAt }
        return analysisChanges[series]
    }

    public func sources(for metric: HealthMeasurement.Metric) -> [HealthMeasurement.Source] {
        let records = history.reversed().filter { $0.metric == metric }.map(\.source)
        return availableSources(records, preferred: preferredSource(for: metric))
    }

    func availableSources(
        _ records: [HealthMeasurement.Source], preferred: HealthMeasurement.Source?
    ) -> [HealthMeasurement.Source] {
        var sources: [String: HealthMeasurement.Source] = [:]
        if let preferred {
            sources[preferred.bundleIdentifier] = preferred
        }
        for source in records {
            sources[source.bundleIdentifier] = source
        }
        return sources.values.sorted {
            ($0.name, $0.bundleIdentifier) < ($1.name, $1.bundleIdentifier)
        }
    }

    public func setPreferredSource(_ bundleIdentifier: String?, for metric: HealthMeasurement.Metric) throws(PreferenceFailure) {
        try setPreferredSource(bundleIdentifier, for: metric, among: sources(for: metric))
    }

    func setPreferredSource(
        _ bundleIdentifier: String?, for metric: HealthMeasurement.Metric, among sources: [HealthMeasurement.Source]
    ) throws(PreferenceFailure) {
        guard var updated = snapshot else { throw .persistence }
        guard updated.preferredSources[metric.rawValue]?.bundleIdentifier != bundleIdentifier else { return }
        if let bundleIdentifier {
            guard let source = sources.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                throw .unknownSource
            }
            updated.preferredSources[metric.rawValue] = source
        } else {
            updated.preferredSources.removeValue(forKey: metric.rawValue)
        }
        var changes = analysisChangeDates(in: updated)
        changes[.health(metric: metric)] = .now
        updated.analysisChanges = changes
        do {
            try persist(updated)
            reconciliationVersion += 1
        } catch {
            throw .persistence
        }
    }

    public func measurements(for metric: HealthMeasurement.Metric) -> [HealthMeasurement] {
        let preferredID = preferredSource(for: metric)?.bundleIdentifier
        return history.filter {
            $0.metric == metric && (preferredID == nil || $0.source.bundleIdentifier == preferredID)
        }
    }

    public func coverage(for metric: HealthMeasurement.Metric, calendar: Calendar = .current) -> Coverage? {
        if metric == .sleepAnalysis {
            return SleepDerivation.coverage(for: sleepEpisodes)
        }
        return Self.sampleCoverage(records: measurements(for: metric), calendar: calendar)
    }

    static func sampleCoverage(records: [HealthMeasurement], calendar: Calendar) -> Coverage? {
        guard let first = records.last?.startDate, let latest = records.first?.startDate else { return nil }
        let measuredDays = Set(records.map { calendar.startOfDay(for: $0.startDate) }).count
        let firstDay = calendar.startOfDay(for: first)
        let lastDay = calendar.startOfDay(for: latest)
        let span = (calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1
        return Coverage(
            recordCount: records.count,
            firstMeasurement: first,
            latestMeasurement: latest,
            firstMeasurementTimeZone: nil,
            latestMeasurementTimeZone: nil,
            measuredDays: measuredDays,
            daysWithoutMeasurements: max(0, span - measuredDays)
        )
    }

    public func requestAccessAndRefresh() async {
        while readState == .loading, !Task.isCancelled { _ = await waitForRead() }
        _ = await load(requestingAccess: true)
    }

    public func refresh() async {
        _ = await refreshForAnalysis()
    }

    public func refreshAfterHealthChange() async {
        if readState == .loading { _ = await waitForRead() }
        _ = await refreshForAnalysis()
    }

    func refreshForAnalysis() async -> ReadState? {
        guard !Task.isCancelled else { return nil }
        if readState == .loading { return await waitForRead() }
        return await load(requestingAccess: false)
    }

    private func waitForRead() async -> ReadState? {
        await withCheckedContinuation { analysisReadWaiters.append($0) }
    }

    private func load(requestingAccess: Bool) async -> ReadState? {
        guard readState != .loading, !Task.isCancelled else { return nil }
        guard let source else {
            readState = .failed(.unavailable)
            reconciliationVersion += 1
            return readState
        }

        readState = .loading
        var failure: HealthMeasurementReadFailure = .persistence
        let completedRead: ReadState?
        do {
            if snapshot == nil, let storeURL {
                snapshot = try Snapshot.load(from: storeURL)
            }
            failure = .request
            if requestingAccess {
                try await source.requestReadAccess()
            }
            failure = .read
            let changes = try await source.readChanges(
                after: snapshot?.anchors ?? [:],
                includingPreviouslySaved: requestingAccess
            )
            try Task.checkCancellation()
            var updated = snapshot ?? Snapshot()
            let previous = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
            var imported = previous
            var touchedIDs: Set<UUID> = []
            for change in changes {
                updated.anchors[change.queryID] = change.anchor
                updated.deletedRecordIDs.formUnion(change.deleted)
            }
            for change in changes {
                for id in change.deleted {
                    imported.removeValue(forKey: id)
                    touchedIDs.insert(id)
                }
                for record in change.added where !updated.deletedRecordIDs.contains(record.id) {
                    imported[record.id] = record
                    touchedIDs.insert(record.id)
                }
            }
            updated.records = imported.values.sorted {
                let left = ($0.startDate, $0.endDate)
                let right = ($1.startDate, $1.endDate)
                return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
            }
            if updated.sleepFallbackTimeZoneIdentifier == nil,
               updated.records.contains(where: { $0.metric == .sleepAnalysis }) {
                updated.sleepFallbackTimeZoneIdentifier = TimeZone.current.identifier
            }
            updated.workouts = reconciledWorkouts(changes, deletedIDs: updated.deletedRecordIDs)
            let checkedAt = Date.now
            var analysisChanges = analysisChangeDates(in: updated)
            for id in touchedIDs where previous[id] != imported[id] {
                for record in [previous[id], imported[id]].compactMap({ $0 }) {
                    let source = record.source.bundleIdentifier
                    analysisChanges[.health(metric: record.metric, sourceBundleIdentifier: source)] = checkedAt
                    if preferredSource(for: record.metric).map({ $0.bundleIdentifier == source }) ?? true {
                        analysisChanges[.health(metric: record.metric)] = checkedAt
                    }
                }
            }
            updated.analysisChanges = analysisChanges
            updated.lastSuccessfulReadAt = checkedAt
            failure = .persistence
            try persist(updated)
            readState = .loaded
            completedRead = readState
        } catch is CancellationError {
            readState = .failed(.interrupted)
            completedRead = readState
        } catch {
            readState = .failed(error as? HealthMeasurementReadFailure ?? failure)
            completedRead = readState
        }
        reconciliationVersion += 1
        let waiters = analysisReadWaiters
        analysisReadWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: completedRead)
        }
        return completedRead
    }

    private func analysisChangeDates(in snapshot: Snapshot) -> [AnalysisSeriesID: Date] {
        if let changes = snapshot.analysisChanges { return changes }
        guard let checkedAt = snapshot.lastSuccessfulReadAt else { return [:] }
        return snapshot.records.reduce(into: [:]) { changes, record in
            changes[.health(metric: record.metric)] = checkedAt
            changes[.health(metric: record.metric, sourceBundleIdentifier: record.source.bundleIdentifier)] = checkedAt
        }
    }

    private func reconciledWorkouts(_ changes: [HealthMeasurementChanges], deletedIDs: Set<UUID>) -> [HealthWorkout] {
        var imported = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
        for change in changes {
            for id in change.deleted {
                imported.removeValue(forKey: id)
            }
            for workout in change.workouts where !deletedIDs.contains(workout.id) {
                imported[workout.id] = workout
            }
        }
        return imported.values.sorted {
            if $0.endDate != $1.endDate { return $0.endDate > $1.endDate }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func persist(_ updated: Snapshot) throws {
        if let storeURL {
            let directory = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var options: Data.WritingOptions = .atomic
            #if os(iOS)
            var localDirectory = directory
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try localDirectory.setResourceValues(resources)
            options.insert(.completeFileProtection)
            #endif
            try JSONEncoder().encode(updated).write(to: storeURL, options: options)
        }
        snapshot = updated
    }
}
