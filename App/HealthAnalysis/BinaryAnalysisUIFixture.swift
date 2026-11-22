#if DEBUG
import Foundation
import HealthAnalysisCore

enum BinaryAnalysisUIFixture {
    @MainActor static func applicationForLaunch() -> HealthAnalysisApplication? {
        guard ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_BINARY_UI_FIXTURE"] == "1" else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> ManualLogDay {
            ManualLogDay(calendar.date(byAdding: .day, value: offset - 161, to: today)!, timeZone: calendar.timeZone)
        }
        let app = HealthAnalysisApplication()
        let meal = try! app.manualLog.createTypedVariable(
            name: "Late meal", kind: .yesNo, defaultValue: .yesNo(false), startsOn: day(0)
        )
        let shift = try! app.manualLog.createTypedVariable(
            name: "Night shift", kind: .yesNo, defaultValue: .yesNo(false), startsOn: day(0)
        )
        let headache = try! app.manualLog.createTypedVariable(
            name: "Headache", kind: .yesNo, defaultValue: .yesNo(false), startsOn: day(1)
        )
        let yesCounts = [8, 24, 16, 32]
        for index in 0..<160 {
            let group = index % 4
            if index > 0 {
                app.manualLog.editTypedEntry(meal.id, on: day(index), value: .yesNo(group % 2 == 1))
            }
            app.manualLog.editTypedEntry(shift.id, on: day(index), value: .yesNo(group >= 2))
            let rank = (index / 4 * 13 + 20) % 40
            app.manualLog.editTypedEntry(headache.id, on: day(index + 1), value: .yesNo(rank < yesCounts[group]))
        }
        return app
    }
}
#endif
