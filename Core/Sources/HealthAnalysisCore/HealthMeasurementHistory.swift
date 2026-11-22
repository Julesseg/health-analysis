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

        static func load(from url: URL) throws -> Self {
            do {
                return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return Self()
            }
        }
    }

    public private(set) var readState: ReadState = .idle
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
        if let bundleIdentifier {
            guard let source = sources.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                throw .unknownSource
            }
            updated.preferredSources[metric.rawValue] = source
        } else {
            updated.preferredSources.removeValue(forKey: metric.rawValue)
        }
        do {
            try persist(updated)
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
        await load(requestingAccess: true)
    }

    public func refresh() async {
        await load(requestingAccess: false)
    }

    private func load(requestingAccess: Bool) async {
        guard readState != .loading else { return }
        guard let source else {
            readState = .failed(.unavailable)
            return
        }

        let previousState = readState
        readState = .loading
        var failure: HealthMeasurementReadFailure = .persistence
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
            var imported = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
            for change in changes {
                updated.anchors[change.queryID] = change.anchor
                updated.deletedRecordIDs.formUnion(change.deleted)
            }
            for change in changes {
                for id in change.deleted {
                    imported.removeValue(forKey: id)
                }
                for record in change.added where !updated.deletedRecordIDs.contains(record.id) {
                    imported[record.id] = record
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
            updated.lastSuccessfulReadAt = .now
            failure = .persistence
            try persist(updated)
            readState = .loaded
        } catch is CancellationError {
            readState = previousState
        } catch {
            readState = .failed(error as? HealthMeasurementReadFailure ?? failure)
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
