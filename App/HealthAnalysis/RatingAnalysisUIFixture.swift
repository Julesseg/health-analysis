#if DEBUG
import Foundation
import HealthAnalysisCore

enum RatingAnalysisUIFixture {
    @MainActor static func applicationForLaunch() -> HealthAnalysisApplication? {
        guard ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_RATING_UI_FIXTURE"] == "1" else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: .now)
        let first = calendar.date(byAdding: .day, value: -121, to: today)!
        func day(_ offset: Int) -> ManualLogDay {
            ManualLogDay(calendar.date(byAdding: .day, value: offset, to: first)!, timeZone: calendar.timeZone)
        }
        let app = HealthAnalysisApplication()
        let stress = try! app.manualLog.createTypedVariable(
            name: "Stress", kind: .rating(1...5), defaultValue: .rating(2), startsOn: day(0)
        )
        let energy = try! app.manualLog.createTypedVariable(
            name: "Energy", kind: .rating(1...5), defaultValue: .rating(2), startsOn: day(1)
        )
        for index in 0..<120 {
            let highStress = index % 2
            let cycle = index / 2 % 10
            if index != 119 {
                let level = highStress == 0 ? 1 + cycle % 2 : 3 + cycle % 3
                app.manualLog.editTypedEntry(stress.id, on: day(index), value: .rating(level))
            }
            let highEnergy = cycle < 2 + 5 * highStress
            app.manualLog.editTypedEntry(energy.id, on: day(index + 1), value: .rating(highEnergy ? 3 + cycle % 3 : 1 + cycle % 2))
        }
        return app
    }
}
#endif
