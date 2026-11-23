#if DEBUG
import Foundation
import HealthAnalysisCore

enum DiscoveryUIFixture {
    private static var mode: String? { ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_DISCOVERY_UI_FIXTURE"] }
    static var checksOnActivation: Bool { mode == "foreground-refresh" }

    @MainActor static func applicationForLaunch() -> HealthAnalysisApplication? {
        guard mode == "1" || checksOnActivation || reassesses else { return nil }
        let calendar = Calendar.current
        let timeZone = calendar.timeZone
        let today = calendar.startOfDay(for: .now)
        let cutoff = calendar.date(byAdding: .day, value: reassesses ? -80 : -1, to: today)!
        let first = calendar.date(byAdding: .day, value: -395, to: cutoff)!
        let totalDays = reassesses ? 474 : 395
        let source = HealthMeasurement.Source(name: "Discovery fixture watch", bundleIdentifier: "fixture.discovery-ui")
        let days = (0..<totalDays).map { index in
            let inputDate = calendar.date(byAdding: .day, value: index, to: first)!
            let next = calendar.date(byAdding: .day, value: 1, to: inputDate)!
            let outputDate = calendar.date(byAdding: .hour, value: 9, to: next)!
            let amount = 100 + index * 71 % 251
            let signal = index < 395 ? 60 + 0.04 * Double(amount) : 90 - 0.04 * Double(amount)
            let bpm = signal + Double((index + 1) * 13 % 17) / 20
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
        for (index, day) in days.enumerated() where !reassesses || index < totalDays - 1 {
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

    @MainActor static func prepareSavedDiscovery(in application: HealthAnalysisApplication) async {
        guard reassesses, application.savedAnalyses.questions.isEmpty else { return }
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -80, to: calendar.startOfDay(for: .now))!
        let cutoff = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        await application.healthMeasurements.refresh()
        guard let report = await application.discover(asOf: cutoff, timeZone: calendar.timeZone),
              let finding = report.findings.first(where: { $0.configuration.behaviorWindow == .precedingDay }),
              let question = try? application.savedAnalyses.save(finding.configuration, completed: finding.completed)
        else { return }
        try? application.savedAnalyses.setPinned(true, for: question.id)
    }

    private static var reassesses: Bool {
        ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_DISCOVERY_REASSESSMENT_UI_FIXTURE"] == "1"
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
