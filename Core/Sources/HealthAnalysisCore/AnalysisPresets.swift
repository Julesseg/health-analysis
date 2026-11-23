import Foundation

extension HealthAnalysisApplication {
    @MainActor public func analysisPresets(
        timeZone: TimeZone = .current, asOf: Date = .now
    ) -> [AnalysisConfiguration] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let variables = analysisVariables.filter { $0.id.sourceIdentifier == nil }
        let inputs = variables.filter(\.supportsInput).flatMap { variable -> [AnalysisSeriesID] in
            switch variable.id {
            case .manualTyped where variable.kind == .tracked(.timeOfDay):
                return [variable.id]
            case .manualQuantity(let id), .manualTyped(let id):
                return manualLog.suggestion(for: id, named: variable.name) == nil ? [] : [variable.id]
            case .activity:
                return readablePresetSeries(for: variable.id, asOf: asOf, calendar: calendar)
            case .health, .sleepTiming:
                return []
            }
        }
        guard !inputs.isEmpty else { return [] }

        return variables.filter {
            switch $0.id {
            case .health, .sleepTiming: $0.supportsOutput
            default: false
            }
        }.flatMap { variable in
            readablePresetSeries(for: variable.id, asOf: asOf, calendar: calendar).flatMap { output in
                inputs.compactMap { input in
                    let configuration = AnalysisConfiguration(output: output, inputs: [input], timeZone: timeZone)
                    guard (try? validatedAnalysisSeries(for: configuration)) != nil else { return nil }
                    return configuration
                }
            }
        }
    }

    @MainActor private func readablePresetSeries(
        for series: AnalysisSeriesID, asOf: Date, calendar: Calendar
    ) -> [AnalysisSeriesID] {
        let (records, preferred) = importedAnalysisOutputs(for: series, asOf: asOf, calendar: calendar)
        let sources = Set(records.compactMap { $0.source?.bundleIdentifier })
        if let preferred = series.sourceIdentifier ?? preferred { return sources.contains(preferred) ? [series] : [] }
        if sources.count == 1 { return [series] }
        return sources.sorted().map { series.selectingSource($0) }
    }
}
