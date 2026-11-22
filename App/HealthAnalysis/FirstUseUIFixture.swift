#if DEBUG
import Foundation
import HealthAnalysisCore

enum FirstUseUIFixture {
    @MainActor
    static func applicationForLaunch() -> HealthAnalysisApplication? {
        guard ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_FIRST_USE_UI_FIXTURE"] == "1" else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let first = calendar.date(byAdding: .day, value: -31, to: calendar.startOfDay(for: .now))!
        let source = HealthMeasurement.Source(name: "Fixture watch", bundleIdentifier: "fixture.first-use")
        let days = (0..<30).map { index in
            let inputDay = calendar.date(byAdding: .day, value: index, to: first)!
            let nextDay = calendar.date(byAdding: .day, value: 1, to: inputDay)!
            let outputDate = calendar.date(byAdding: .hour, value: 9, to: nextDay)!
            return (
                inputDay: ManualLogDay(inputDay, timeZone: calendar.timeZone),
                outputDate: outputDate,
                duration: 15 + (index % 5) * 10
            )
        }
        let heartRate = days.enumerated().compactMap { index, day -> HealthMeasurement? in
            guard index != 7 else { return nil }
            return HealthMeasurement(
                id: UUID(), metric: .restingHeartRate, value: 60 + Double(day.duration) / 10, unit: .beatsPerMinute,
                startDate: day.outputDate, endDate: day.outputDate, source: source
            )
        }
        let hrv = HealthMeasurement(
            id: UUID(), metric: HRVSeries.StoredType.sdnn.metric, value: 43, unit: .milliseconds,
            startDate: days[0].outputDate, endDate: days[0].outputDate, source: source
        )
        let app = HealthAnalysisApplication(healthSource: Source(records: heartRate + [hrv]))
        let activity = try! app.manualLog.createQuantity(
            name: "Workout duration", unit: "min", defaultValue: 0, startsOn: days[0].inputDay
        )
        for day in days {
            app.manualLog.editQuantity(
                activity.id, on: day.inputDay, text: String(day.duration), locale: Locale(identifier: "en_US")
            )
        }
        return app
    }

    private struct Source: HealthMeasurementSource {
        let records: [HealthMeasurement]

        func requestReadAccess() async throws {}

        func readChanges(
            after anchors: [String: Data], includingPreviouslySaved: Bool
        ) async throws -> [HealthMeasurementChanges] {
            [.init(queryID: "firstUseFixture", anchor: Data([1]), added: records)]
        }
    }
}
#endif
