#if DEBUG
import Foundation
import HealthAnalysisCore

enum HealthMeasurementUIFixture: String {
    case loading
    case empty
    case protectedAfterImport
    case sleepHistory

    static func configurationForLaunch() -> (source: any HealthMeasurementSource, storeURL: URL)? {
        let environment = ProcessInfo.processInfo.environment
        guard let name = environment["HEALTH_MEASUREMENT_UI_FIXTURE"],
              let fixture = Self(rawValue: name) else { return nil }
        let id = environment["HEALTH_MEASUREMENT_UI_FIXTURE_STORE"].flatMap(UUID.init(uuidString:)) ?? UUID()
        let url = URL.temporaryDirectory
            .appending(path: "HealthMeasurementUITests", directoryHint: .isDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
            .appending(path: "measurements.json", directoryHint: .notDirectory)
        let source: any HealthMeasurementSource = fixture == .sleepHistory
            ? SleepHistoryUIFixture()
            : Source(fixture: fixture)
        return (source, url)
    }

    private struct Source: HealthMeasurementSource {
        private static let queryID = "restingHeartRate"
        let fixture: HealthMeasurementUIFixture

        func requestReadAccess() async throws {}

        func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
            let records = try await samples(after: anchors[Self.queryID])
            return [.init(queryID: Self.queryID, anchor: Data([1]), added: records)]
        }

        private func samples(after anchor: Data?) async throws -> [HealthMeasurement] {
            switch fixture {
            case .loading:
                try await Task.sleep(for: .seconds(30))
                return []
            case .empty, .sleepHistory:
                return []
            case .protectedAfterImport:
                guard anchor == nil else { throw HealthMeasurementReadFailure.protectedData }
                let date = Date(timeIntervalSince1970: 1_763_366_400)
                return [
                    HealthMeasurement(
                        id: UUID(),
                        metric: .restingHeartRate,
                        value: 62,
                        unit: .beatsPerMinute,
                        startDate: date,
                        endDate: date,
                        source: .init(name: "Apple Watch", bundleIdentifier: "fixture.watch")
                    ),
                    HealthMeasurement(
                        id: UUID(),
                        metric: .restingHeartRate,
                        value: 58,
                        unit: .beatsPerMinute,
                        startDate: date.addingTimeInterval(-172_800),
                        endDate: date.addingTimeInterval(-169_200),
                        source: .init(name: "Livity", bundleIdentifier: "fixture.livity")
                    ),
                ]
            }
        }
    }
}
#endif
