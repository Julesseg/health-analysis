#if DEBUG
import Foundation
import HealthAnalysisCore

enum DiscoveryUIFixture {
    @MainActor static func applicationForLaunch() -> HealthAnalysisApplication? {
        guard ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_DISCOVERY_UI_FIXTURE"] == "1" else { return nil }
        let calendar = Calendar.current
        let timeZone = calendar.timeZone
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now))!
        let first = calendar.date(byAdding: .day, value: -395, to: yesterday)!
        let source = HealthMeasurement.Source(name: "Discovery fixture watch", bundleIdentifier: "fixture.discovery-ui")
        let days = (0..<395).map { index in
            let inputDate = calendar.date(byAdding: .day, value: index, to: first)!
            let next = calendar.date(byAdding: .day, value: 1, to: inputDate)!
            let outputDate = calendar.date(byAdding: .hour, value: 9, to: next)!
            let amount = 100 + index * 71 % 251
            let bpm = 60 + 0.04 * Double(amount) + Double((index + 1) * 13 % 17) / 20
            return (
                date: ManualLogDay(inputDate, timeZone: timeZone), amount: amount,
                measurement: HealthMeasurement(
                    id: UUID(), metric: .restingHeartRate, value: bpm, unit: .beatsPerMinute,
                    startDate: outputDate, endDate: outputDate, source: source
                )
            )
        }
        let application = HealthAnalysisApplication(healthSource: Source(records: days.map(\.measurement)))
        let caffeine = try! application.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 0, startsOn: days[0].date
        )
        for day in days {
            application.manualLog.editQuantity(
                caffeine.id, on: day.date, text: String(day.amount), locale: Locale(identifier: "en_US_POSIX")
            )
        }
        return application
    }

    private struct Source: HealthMeasurementSource {
        let records: [HealthMeasurement]

        func requestReadAccess() async throws {}

        func readChanges(
            after anchors: [String: Data], includingPreviouslySaved: Bool
        ) async throws -> [HealthMeasurementChanges] {
            [.init(queryID: "restingHeartRate", anchor: Data([1]), added: records)]
        }
    }
}
#endif
