import Foundation

extension HealthAnalysisApplication {
    @MainActor public func analysisPresets(
        timeZone: TimeZone = .current, asOf: Date = .now
    ) -> [AnalysisConfiguration] {
        let inputs = analysisNumericQuantities.compactMap { quantity -> AnalysisSeriesID? in
            guard manualLog.suggestion(for: quantity.id, named: quantity.name) != nil else { return nil }
            return .manualQuantity(quantity.id)
        }
        guard !inputs.isEmpty else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return analysisOutputChoices.flatMap { output in
            readablePresetOutputs(for: output, asOf: asOf, calendar: calendar).flatMap { output in
                inputs.compactMap { input in
                    let configuration = AnalysisConfiguration(output: output, inputs: [input], timeZone: timeZone)
                    guard (try? analysisQuantities(for: configuration)) != nil else { return nil }
                    return configuration
                }
            }
        }
    }

    @MainActor private func readablePresetOutputs(
        for output: AnalysisSeriesID, asOf: Date, calendar: Calendar
    ) -> [AnalysisSeriesID] {
        guard case .health(let metric, let sourceID) = output else { return [] }
        let records = healthAnalysisOutputs(for: metric, asOf: asOf, calendar: calendar)
        let sources = Set(records.map(\.source.bundleIdentifier))
        if let preferred = sourceID ?? healthMeasurements.preferredSource(for: metric)?.bundleIdentifier {
            return sources.contains(preferred) ? [output] : []
        }
        if sources.count == 1 { return [output] }
        return sources.sorted().map { .health(metric: metric, sourceBundleIdentifier: $0) }
    }
}
