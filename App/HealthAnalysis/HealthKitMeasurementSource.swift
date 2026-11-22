import Foundation
import HealthAnalysisCore
import HealthKit
import OSLog

struct HealthKitMeasurementSource: HealthMeasurementSource {
    private let store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    private static let logger = Logger(subsystem: "HealthAnalysis", category: "HealthKit")

    private static let queries: [HealthKitMeasurementQuery] = [
        restingHeartRate,
        .sleep,
        HealthKitWorkoutStream.query,
    ] + HealthKitHRVStream.queries

    private static let restingHeartRate: HealthKitMeasurementQuery = {
        let type = HKQuantityType(.restingHeartRate)
        return HealthKitMeasurementQuery(type: type, predicate: .quantitySample(type: type)) { sample in
            let unit = HKUnit.count().unitDivided(by: .minute())
            let source = sample.sourceRevision.source
            return HealthMeasurement(
                id: sample.uuid,
                metric: .restingHeartRate,
                value: sample.quantity.doubleValue(for: unit),
                unit: .beatsPerMinute,
                startDate: sample.startDate,
                endDate: sample.endDate,
                source: .init(name: source.name, bundleIdentifier: source.bundleIdentifier)
            )
        }
    }()

    func requestReadAccess() async throws {
        guard let store else { throw HealthMeasurementReadFailure.unavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: Set(Self.queries.flatMap(\.readTypes)))
            enableBackgroundDelivery(in: store)
        } catch {
            throw availabilityFailure(for: error) ?? error
        }
    }

    func observeChanges(_ receive: @escaping @Sendable (Bool) -> Void) {
        guard let store else { return }
        for stream in Self.queries {
            let type = stream.sampleType
            let observer = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                receive(error == nil)
                completion()
            }
            store.execute(observer)
        }
        enableBackgroundDelivery(in: store)
    }

    private func enableBackgroundDelivery(in store: HKHealthStore) {
        #if !targetEnvironment(simulator)
        for stream in Self.queries {
            let type = stream.sampleType
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { enabled, _ in
                if !enabled {
                    Self.logger.notice("Background delivery was unavailable for \(type.identifier, privacy: .public).")
                }
            }
        }
        #endif
    }

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        guard let store else { throw HealthMeasurementReadFailure.unavailable }
        do {
            var changes: [HealthMeasurementChanges] = []
            for query in Self.queries {
                try Task.checkCancellation()
                changes.append(try await query.changes(
                    in: store, after: anchors, includingPreviouslySaved: includingPreviouslySaved
                ))
            }
            return changes
        } catch {
            throw availabilityFailure(for: error) ?? error
        }
    }

    private func availabilityFailure(for error: any Error) -> HealthMeasurementReadFailure? {
        switch (error as? HKError)?.code {
        case .errorDatabaseInaccessible: .protectedData
        case .errorHealthDataUnavailable, .errorHealthDataRestricted: .unavailable
        default: nil
        }
    }
}
