import Foundation

extension HealthAnalysisApplication {
    @MainActor public func analysisPresets(
        timeZone: TimeZone = .current, asOf: Date = .now
    ) -> [AnalysisConfiguration] {
        let variables = analysisVariables
        let inputs = variables.filter(\.supportsInput).compactMap { variable -> AnalysisSeriesID? in
            switch variable.id {
            case .manualTyped where variable.kind == .tracked(.timeOfDay):
                return variable.id
            case .manualQuantity(let id), .manualTyped(let id):
                return manualLog.suggestion(for: id, named: variable.name) == nil ? nil : variable.id
            case .health, .sleepTiming:
                return nil
            }
        }
        guard !inputs.isEmpty else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return variables.filter(\.supportsOutput).flatMap { variable in
            readablePresetOutputs(for: variable.id, asOf: asOf, calendar: calendar).flatMap { output in
                inputs.compactMap { input in
                    let configuration = AnalysisConfiguration(output: output, inputs: [input], timeZone: timeZone)
                    guard (try? validatedAnalysisSeries(for: configuration)) != nil else { return nil }
                    return configuration
                }
            }
        }
    }

    @MainActor private func readablePresetOutputs(
        for output: AnalysisSeriesID, asOf: Date, calendar: Calendar
    ) -> [AnalysisSeriesID] {
        let (metric, sourceID, timing): (HealthMeasurement.Metric, String?, SleepTiming?)
        switch output {
        case .health(let selectedMetric, let selectedSource):
            (metric, sourceID, timing) = (selectedMetric, selectedSource, nil)
        case .sleepTiming(let event, let selectedSource):
            (metric, sourceID, timing) = (.sleepAnalysis, selectedSource, event)
        default:
            return []
        }
        let records = healthAnalysisOutputs(for: metric, asOf: asOf, calendar: calendar, timing: timing)
        let sources = Set(records.compactMap { $0.source?.bundleIdentifier })
        if let preferred = sourceID ?? healthMeasurements.preferredSource(for: metric)?.bundleIdentifier {
            return sources.contains(preferred) ? [output] : []
        }
        if sources.count == 1 { return [output] }
        return sources.sorted().map { source in
            if let timing { return .sleepTiming(timing, sourceBundleIdentifier: source) }
            return .health(metric: metric, sourceBundleIdentifier: source)
        }
    }
}
