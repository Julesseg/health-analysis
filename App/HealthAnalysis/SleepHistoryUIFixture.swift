#if DEBUG
import Foundation
import HealthAnalysisCore

struct SleepHistoryUIFixture: HealthMeasurementSource {
    private static let queryID = "sleepAnalysis"

    func requestReadAccess() async throws {}

    func readChanges(after anchors: [String: Data], includingPreviouslySaved: Bool) async throws -> [HealthMeasurementChanges] {
        switch anchors[Self.queryID] {
        case nil:
            [.init(queryID: Self.queryID, anchor: Data([1]), added: [
                stage(1, .inBed, "2026-03-28T21:00:00Z", "2026-03-29T07:00:00Z"),
                stage(2, .asleepUnspecified, "2026-03-28T22:30:00Z", "2026-03-29T05:30:00Z"),
                stage(3, .asleepCore, "2026-03-29T00:00:00Z", "2026-03-29T02:30:00Z"),
                stage(4, .awake, "2026-03-29T01:15:00Z", "2026-03-29T01:45:00Z"),
                stage(5, .asleepREM, "2026-03-29T05:15:00Z", "2026-03-29T06:00:00Z"),
                stage(6, .asleepCore, "2026-03-30T13:00:00Z", "2026-03-30T18:00:00Z", zone: "Asia/Tokyo"),
                stage(7, .asleepDeep, "2026-03-30T18:00:00Z", "2026-03-30T21:00:00Z", zone: "Asia/Tokyo"),
            ])]
        case Data([1]):
            [.init(queryID: Self.queryID, anchor: Data([2]), added: [
                stage(8, .asleepDeep, "2026-03-30T18:00:00Z", "2026-03-30T19:00:00Z", zone: "Asia/Tokyo"),
            ], deleted: [id(7)])]
        default:
            [.init(queryID: Self.queryID, anchor: Data([2]), added: [])]
        }
    }

    private func stage(
        _ number: Int, _ stage: SleepStage, _ start: String, _ end: String, zone: String = "Europe/Paris"
    ) -> HealthMeasurement {
        let formatter = ISO8601DateFormatter()
        return HealthMeasurement(
            id: id(number),
            sleepStage: stage,
            startDate: formatter.date(from: start)!,
            endDate: formatter.date(from: end)!,
            source: .init(name: "Fixture Watch", bundleIdentifier: "fixture.sleep.watch"),
            timeZoneIdentifier: zone
        )
    }

    private func id(_ number: Int) -> UUID {
        UUID(uuidString: "11000000-0000-0000-0000-00000000000\(number)")!
    }
}
#endif
