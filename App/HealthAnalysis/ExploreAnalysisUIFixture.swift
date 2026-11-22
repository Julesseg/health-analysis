#if DEBUG
import Foundation
import HealthAnalysisCore

enum ExploreAnalysisUIFixture {
    @MainActor
    static func applicationForLaunch() -> HealthAnalysisApplication? {
        let environment = ProcessInfo.processInfo.environment
        let interaction = InteractionScenario(rawValue: environment["HEALTH_ANALYSIS_INTERACTION_UI_FIXTURE"] ?? "")
        guard environment["HEALTH_ANALYSIS_EXPLORE_UI_FIXTURE"] == "1" || interaction != nil else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let first = calendar.date(byAdding: .day, value: -113, to: calendar.startOfDay(for: .now))!
        let source = HealthMeasurement.Source(name: "Fixture watch", bundleIdentifier: "fixture.explore")
        let dayCount = interaction == nil ? 112 : 144
        let days = (0..<dayCount).map { index in
            let inputDate = calendar.date(byAdding: .day, value: index, to: first)!
            let next = calendar.date(byAdding: .day, value: 1, to: inputDate)!
            let outputDate = calendar.date(byAdding: .hour, value: 9, to: next)!
            let amount = 50 + (index % 5) * 50
            let fluids = 1 + index % 3
            let exercise = 15 + index % 13 * 5
            let supplement = 50 + index % 11 * 10
            let bpm = 60 + Double(amount) / 50 + Double(index % 7 - 3) * 0.17
                + Double(fluids) * 0.2 - Double(exercise) * 0.01 + Double(supplement) * 0.003
            let values = interaction?.values(on: index) ?? (amounts: [amount, fluids, exercise, supplement], bpm: bpm)
            return (
                day: ManualLogDay(inputDate, timeZone: calendar.timeZone),
                amounts: values.amounts,
                measurement: HealthMeasurement(
                    id: UUID(), metric: .restingHeartRate, value: values.bpm, unit: .beatsPerMinute,
                    startDate: outputDate, endDate: outputDate, source: source
                )
            )
        }
        let application = HealthAnalysisApplication(healthSource: Source(records: days.map(\.measurement)))
        let quantities = [("Caffeine", "mg"), ("Fluids", "L"), ("Exercise log", "min"), ("Supplement", "mg")]
            .map { name, unit in
                try! application.manualLog.createQuantity(name: name, unit: unit, defaultValue: 0, startsOn: days[0].day)
            }
        let locale = Locale(identifier: "en_US")
        for day in days {
            for (quantity, amount) in zip(quantities, day.amounts) {
                application.manualLog.editQuantity(quantity.id, on: day.day, text: String(amount), locale: locale)
            }
        }
        if environment["HEALTH_ANALYSIS_SAVED_ANALYSIS_UI_FIXTURE"] == "1" {
            _ = try! application.manualLog.createQuantity(
                name: "Evening caffeine", unit: "mg", defaultValue: 0, startsOn: days[0].day
            )
        }
        return application
    }

    private enum InteractionScenario: String {
        case planted
        case null
        case collinear
        case sparse

        func values(on index: Int) -> (amounts: [Int], bpm: Double) {
            var caffeine = 100 + index % 3 * 50
            var fluids = 1 + index / 3 % 3
            if self == .sparse, index % 9 == 6, index >= 27 {
                if (index / 9).isMultiple(of: 2) {
                    caffeine = 150
                } else {
                    fluids = 2
                }
            }
            let exercise = self == .collinear ? caffeine / 5 : 15 + index / 9 % 2 * 20
            let supplement = 60 + index / 18 % 2 * 20
            let noise = index / 36 % 2 == 0 ? -0.2 : 0.2
            let caffeineChange = Double(caffeine - 150) / 100
            let fluidChange = Double(fluids - 2)
            let strength: Double = self == .null ? 0 : 3
            let bpm = 65 + 5 * caffeineChange + 0.7 * fluidChange - 0.04 * Double(exercise - 25)
                + strength * caffeineChange * fluidChange + noise
            return ([caffeine, fluids, exercise, supplement], bpm)
        }
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
