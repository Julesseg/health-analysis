#if DEBUG
import Foundation
import HealthAnalysisCore

enum CountAnalysisUIFixture {
    @MainActor static func applicationForLaunch() -> HealthAnalysisApplication? {
        guard ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_COUNT_UI_FIXTURE"] == "1" else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: .now)
        let first = calendar.date(byAdding: .day, value: -121, to: today)!
        func day(_ offset: Int) -> ManualLogDay {
            ManualLogDay(calendar.date(byAdding: .day, value: offset, to: first)!, timeZone: calendar.timeZone)
        }
        let app = HealthAnalysisApplication()
        let coffees = try! app.manualLog.createTypedVariable(
            name: "Coffees", kind: .count, defaultValue: .count(0), startsOn: day(0)
        )
        let headaches = try! app.manualLog.createTypedVariable(
            name: "Headaches", kind: .count, defaultValue: .count(0), startsOn: day(1)
        )
        for index in 0..<120 {
            let input = index % 2
            app.manualLog.editTypedEntry(coffees.id, on: day(index), value: .count(input))
            if index != 10 {
                let output = 1 + input + index / 2 % 3 - 1
                app.manualLog.editTypedEntry(headaches.id, on: day(index + 1), value: .count(output))
            }
        }
        return app
    }
}
#endif
