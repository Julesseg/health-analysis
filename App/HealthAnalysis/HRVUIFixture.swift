#if DEBUG
import Foundation
import HealthAnalysisCore

struct HRVUIFixture: HealthMeasurementSource {
    func requestReadAccess() async throws {}

    func readChanges(
        after anchors: [String: Data], includingPreviouslySaved: Bool
    ) async throws -> [HealthMeasurementChanges] {
        let date = Date(timeIntervalSince1970: 1_763_366_400)
        return [
            .init(queryID: "sdnn", anchor: Data([1]), added: [
                sample(.sdnn, id: "92E81B9E-55ED-46E7-9C33-B0EB6DDFC001", start: date, value: 42),
                sample(.sdnn, id: "92E81B9E-55ED-46E7-9C33-B0EB6DDFC002", start: date - 172_800, value: 45),
            ]),
            .init(queryID: "rmssd", anchor: Data([1]), added: [
                sample(.rmssd, id: "92E81B9E-55ED-46E7-9C33-B0EB6DDFC003", start: date, value: 51),
            ]),
        ]
    }

    private func sample(_ type: HRVSeries.StoredType, id: String, start: Date, value: Double) -> HealthMeasurement {
        HealthMeasurement(
            id: UUID(uuidString: id)!,
            metric: type.metric,
            value: value,
            unit: .milliseconds,
            startDate: start,
            endDate: start + 300,
            source: .init(name: "Livity", bundleIdentifier: "fixture.livity"),
            timeZoneIdentifier: "Europe/Paris",
            sourceRevision: .init(version: "1.2", productType: "iPhoneFixture", operatingSystemVersion: "27.0.0"),
            hrvProvenance: .init(quantityCount: 1, syncIdentifier: id, syncVersion: 2)
        )
    }
}
#endif
