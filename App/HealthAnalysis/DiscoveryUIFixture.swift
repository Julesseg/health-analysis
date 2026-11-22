#if DEBUG
import Foundation
import HealthAnalysisCore

enum DiscoveryUIFixture {
    private static var mode: String? { ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_DISCOVERY_UI_FIXTURE"] }
    static var checksOnActivation: Bool { mode == "foreground-refresh" }

    @MainActor static func applicationForLaunch() -> HealthAnalysisApplication? {
        guard mode == "1" || checksOnActivation else { return nil }
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
        let application = HealthAnalysisApplication(healthSource: Source(
            records: days.map(\.measurement), exercisesRefresh: checksOnActivation
        ))
        let caffeine = try! application.manualLog.createQuantity(
            name: "Caffeine", unit: "mg", defaultValue: 0, startsOn: days[0].date
        )
        for day in days {
            application.manualLog.editQuantity(
                caffeine.id, on: day.date, text: String(day.amount), locale: Locale(identifier: "en_US_POSIX")
            )
        }
        if checksOnActivation {
            let question = try! application.savedAnalyses.save(.init(
                output: .health(metric: .restingHeartRate), inputs: [.manualQuantity(caffeine.id)], timeZone: timeZone
            ))
            try! application.savedAnalyses.setPinned(true, for: question.id)
        }
        return application
    }

    private actor Source: HealthMeasurementSource {
        let records: [HealthMeasurement]
        let exercisesRefresh: Bool
        var attempts = 0

        init(records: [HealthMeasurement], exercisesRefresh: Bool) {
            self.records = records
            self.exercisesRefresh = exercisesRefresh
        }

        func requestReadAccess() async throws {}

        func readChanges(
            after anchors: [String: Data], includingPreviouslySaved: Bool
        ) async throws -> [HealthMeasurementChanges] {
            attempts += 1
            if !exercisesRefresh || attempts == 1 {
                return [.init(queryID: "restingHeartRate", anchor: Data([1]), added: records)]
            }
            if attempts == 2 { throw HealthMeasurementReadFailure.protectedData }
            return [.init(queryID: "restingHeartRate", anchor: Data([2]), added: [], deleted: records.map(\.id))]
        }
    }
}
#endif
