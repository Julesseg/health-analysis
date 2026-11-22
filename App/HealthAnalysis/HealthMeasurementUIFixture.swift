#if DEBUG
import Foundation
import HealthAnalysisCore

enum HealthMeasurementUIFixture: String {
    case loading
    case empty
    case protectedAfterImport

    static func sourceForLaunch() -> (any HealthMeasurementSource)? {
        guard let name = ProcessInfo.processInfo.environment["HEALTH_MEASUREMENT_UI_FIXTURE"],
              let fixture = Self(rawValue: name) else { return nil }
        return Source(fixture: fixture)
    }

    private actor Source: HealthMeasurementSource {
        let fixture: HealthMeasurementUIFixture
        var didImport = false

        init(fixture: HealthMeasurementUIFixture) {
            self.fixture = fixture
        }

        func requestReadAccess() async throws {}

        func readMeasurements() async throws -> [HealthMeasurement] {
            switch fixture {
            case .loading:
                try await Task.sleep(for: .seconds(30))
                return []
            case .empty:
                return []
            case .protectedAfterImport:
                guard !didImport else { throw HealthMeasurementReadFailure.protectedData }
                didImport = true
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
