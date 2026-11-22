#if DEBUG
import Foundation
import HealthAnalysisCore

enum ClockAnalysisUIFixture {
    @MainActor static func applicationForLaunch() -> HealthAnalysisApplication? {
        guard ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_CLOCK_UI_FIXTURE"] == "1" else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: .now)
        func day(_ index: Int) -> ManualLogDay {
            let date = calendar.date(byAdding: .day, value: index - 81, to: today)!
            return ManualLogDay(date, timeZone: calendar.timeZone)
        }
        func time(_ minute: Int, precision: ManualClockPrecision? = nil) -> ManualTrackingValue {
            .timeOfDay(ManualClockTime(hour: minute / 60, minute: minute % 60), precision: precision)
        }
        let app = HealthAnalysisApplication()
        let caffeine = try! app.manualLog.createTypedVariable(
            name: "Last caffeine", kind: .timeOfDay, defaultValue: time(1410), startsOn: day(0)
        )
        let bedtime = try! app.manualLog.createTypedVariable(
            name: "Bedtime", kind: .timeOfDay, defaultValue: time(1418), startsOn: day(1)
        )
        for index in 0..<80 {
            let late = index % 2
            let precision: ManualClockPrecision = index.isMultiple(of: 5) ? .approximate : .exact
            app.manualLog.editTypedEntry(caffeine.id, on: day(index), value: time(late == 0 ? 1410 : 30, precision: precision))
            let minute = (1420 + 30 * late + (index / 2 % 5 - 2)) % 1440
            app.manualLog.editTypedEntry(bedtime.id, on: day(index + 1), value: time(minute, precision: .approximate))
        }
        return app
    }
}
#endif
