import Foundation

public struct AnalysisVariable: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case quantity(unit: String)
        case tracked(TrackingVariableKind)
    }

    public let id: AnalysisSeriesID
    public let name: String
    public let kind: Kind

    public internal(set) var isCaffeineQuantity: Bool? = nil

    public var supportsInput: Bool {
        switch id {
        case .manualQuantity, .activity: true
        case .manualTyped:
            kind == .tracked(.count) || kind == .tracked(.yesNo) || kind == .tracked(.timeOfDay)
                || kind.ratingThreshold != nil || !categories.isEmpty
        case .health(let metric, _): metric == .restingHeartRate || metric == .sleepAnalysis
        case .sleepTiming: false
        }
    }

    public var supportsOutput: Bool {
        if case .sleepTiming = id { return true }
        return supportsInput
    }

    public var categories: [TrackingCategory] {
        if case .tracked(.category(let options)) = kind { return options }
        return []
    }

    static func sleepTiming(_ timing: SleepTiming, sourceID: String?) -> Self {
        .init(
            id: .sleepTiming(timing, sourceBundleIdentifier: sourceID),
            name: timing == .onset ? "Sleep onset time" : "Wake time", kind: .tracked(.timeOfDay)
        )
    }

    var unit: String {
        switch kind {
        case .quantity(let unit): unit
        case .tracked(.count): "count"
        case .tracked(.timeOfDay): "min"
        case .tracked: ""
        }
    }
}

extension HealthAnalysisApplication {
    @MainActor public var analysisVariables: [AnalysisVariable] {
        let metrics: [AnalysisSeriesID] = [.health(metric: .restingHeartRate), .health(metric: .sleepAnalysis)]
        let sleep = SleepTiming.allCases.map { AnalysisSeriesID.sleepTiming($0) }
        let activity = ActivityTrackingVariable.allCases.filter {
            !healthMeasurements.workoutSources(for: $0).isEmpty
        }.map { AnalysisSeriesID.activity($0) }
        return (metrics + sleep + activity).flatMap { id in
            let sources = analysisSources(for: id)
            let variants = sources.count > 1 ? [id] + sources.map { id.selectingSource($0.bundleIdentifier) } : [id]
            return variants.compactMap { analysisVariable(for: $0) }
        } + manualAnalysisSeries.map(\.variable)
    }

    @MainActor public func analysisVariable(for id: AnalysisSeriesID) -> AnalysisVariable? {
        switch id {
        case .health(.restingHeartRate, _):
            .init(id: id, name: "Resting heart rate", kind: .quantity(unit: "bpm"))
        case .health(.sleepAnalysis, _):
            .init(id: id, name: "Sleep duration", kind: .quantity(unit: "h"))
        case .sleepTiming(let timing, let source):
            .sleepTiming(timing, sourceID: source)
        case .activity(let variable, _):
            .init(id: id, name: variable.analysisName, kind: .quantity(unit: variable == .runningDistance ? "km" : "min"))
        case .manualQuantity, .manualTyped:
            manualAnalysisSeries.first { $0.variable.id == id }?.variable
        default:
            nil
        }
    }

    @MainActor func analysisSources(for id: AnalysisSeriesID) -> [HealthMeasurement.Source] {
        switch id {
        case .health(let metric, _): healthMeasurements.sources(for: metric)
        case .sleepTiming: healthMeasurements.sources(for: .sleepAnalysis)
        case .activity(let variable, _): healthMeasurements.workoutSources(for: variable)
        default: []
        }
    }

    @MainActor var manualAnalysisSeries: [ManualAnalysisSeries] {
        manualLog.quantities.map {
            .quantity($0, caffeine: $0.unit.lowercased() == "mg" && manualLog.suggestion(for: $0.id, named: $0.name) == .caffeine)
        } + manualLog.typedVariables.map(ManualAnalysisSeries.typed)
    }
}

enum ManualAnalysisSeries {
    struct Sample {
        let value: Double?
        let origin: ManualValueOrigin
        var trackingValue: ManualTrackingValue? = nil
    }

    case quantity(TrackingQuantity, caffeine: Bool)
    case typed(TypedTrackingVariable)

    var variable: AnalysisVariable {
        switch self {
        case .quantity(let quantity, let caffeine):
            .init(id: .manualQuantity(quantity.id), name: quantity.name, kind: .quantity(unit: quantity.unit),
                  isCaffeineQuantity: caffeine ? true : nil)
        case .typed(let tracked):
            .init(id: .manualTyped(tracked.id), name: tracked.name, kind: .tracked(tracked.kind))
        }
    }

    @MainActor func numericValue(
        in log: ManualLog, on day: ManualLogDay, category: CategoryAnalysis.Transform? = nil
    ) -> Sample? {
        switch self {
        case .quantity(let quantity, _):
            guard let (amount, origin) = log.analysisValue(for: quantity, on: day) else { return nil }
            let value = NSDecimalNumber(decimal: amount).doubleValue
            guard value.isFinite else { return nil }
            return Sample(value: value, origin: origin)
        case .typed(let variable):
            guard let (value, origin) = log.analysisValue(for: variable, on: day) else { return nil }
            switch (variable.kind, value) {
            case (.count, .count(let count)) where count >= 0:
                return Sample(value: Double(count), origin: origin, trackingValue: value)
            case (.yesNo, .yesNo(let isYes)):
                return Sample(value: BinaryEvent.encode(isYes), origin: origin, trackingValue: value)
            case (.timeOfDay, .timeOfDay(let time, _)) where variable.kind.accepts(value):
                return Sample(value: Double(time.hour * 60 + time.minute), origin: origin, trackingValue: value)
            case (.rating(let levels), .rating(let level)) where levels.contains(level):
                return Sample(value: Double(level), origin: origin, trackingValue: value)
            case (.category(let options), .category(let id)) where options.contains(where: { $0.id == id }):
                guard let category else { return nil }
                return Sample(value: category.encode(id), origin: origin, trackingValue: value)
            default:
                return nil
            }
        }
    }

    @MainActor func firstDay(in log: ManualLog) -> ManualLogDay? {
        switch self {
        case .quantity(let quantity, _): log.quantityDefaults(quantity.id).first?.effectiveOn
        case .typed(let variable): log.typedDefaults(variable.id).first?.effectiveOn
        }
    }
}
