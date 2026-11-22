#if DEBUG
import Foundation
import HealthAnalysisCore

enum ExploreAnalysisUIFixture {
    @MainActor
    static func applicationForLaunch() -> HealthAnalysisApplication? {
        guard ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_EXPLORE_UI_FIXTURE"] == "1" else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let first = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let source = HealthMeasurement.Source(name: "Fixture watch", bundleIdentifier: "fixture.explore")
        let days = (0..<112).map { index in
            let inputDate = calendar.date(byAdding: .day, value: index, to: first)!
            let next = calendar.date(byAdding: .day, value: 1, to: inputDate)!
            let outputDate = calendar.date(byAdding: .hour, value: 9, to: next)!
            let amount = 50 + (index % 5) * 50
            let bpm = 60 + Double(amount) / 50 + Double(index % 7 - 3) * 0.17
            return (
                day: ManualLogDay(inputDate, timeZone: calendar.timeZone),
                amount: amount,
                measurement: HealthMeasurement(
                    id: UUID(), metric: .restingHeartRate, value: bpm, unit: .beatsPerMinute,
                    startDate: outputDate, endDate: outputDate, source: source
                )
            )
        }
        let application = HealthAnalysisApplication(healthSource: Source(records: days.map(\.measurement)))
        let caffeine = try! application.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 0, startsOn: days[0].day
        )
        let locale = Locale(identifier: "en_US")
        for day in days {
            application.manualLog.editQuantity(caffeine.id, on: day.day, text: String(day.amount), locale: locale)
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
