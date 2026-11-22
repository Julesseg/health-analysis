#if DEBUG
import Foundation
import HealthAnalysisCore

enum CategoryAnalysisUIFixture {
    @MainActor static func applicationForLaunch() -> HealthAnalysisApplication? {
        guard ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_CATEGORY_UI_FIXTURE"] == "1" else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let first = calendar.date(byAdding: .day, value: -121, to: today)!
        func day(_ offset: Int) -> ManualLogDay {
            ManualLogDay(calendar.date(byAdding: .day, value: offset, to: first)!, timeZone: calendar.timeZone)
        }
        let app = HealthAnalysisApplication()
        let office = TrackingCategory(name: "Office")
        let home = TrackingCategory(name: "Home")
        let migraine = TrackingCategory(name: "Migraine")
        let tension = TrackingCategory(name: "Tension")
        let none = TrackingCategory(name: "None")
        let input = try! app.manualLog.createTypedVariable(
            name: "Work setting", kind: .category([office, home]), defaultValue: .category(home.id), startsOn: day(0)
        )
        let output = try! app.manualLog.createTypedVariable(
            name: "Headache type", kind: .category([none, tension, migraine]),
            defaultValue: .category(none.id), startsOn: day(1)
        )
        for index in 0..<120 {
            let atOffice = !index.isMultiple(of: 2)
            let repeatIndex = index / 2
            let event = repeatIndex * 17 % 60 < (atOffice ? 36 : 12)
            let observed = event ? migraine : (repeatIndex.isMultiple(of: 2) ? none : tension)
            app.manualLog.editTypedEntry(input.id, on: day(index), value: .category(atOffice ? office.id : home.id))
            app.manualLog.editTypedEntry(output.id, on: day(index + 1), value: .category(observed.id))
        }
        return app
    }
}
#endif
