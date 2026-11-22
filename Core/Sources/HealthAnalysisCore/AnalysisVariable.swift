import Foundation

public struct AnalysisVariable: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case quantity(unit: String)
        case tracked(TrackingVariableKind)
    }

    public let id: AnalysisSeriesID
    public let name: String
    public let kind: Kind

    public var supportsInput: Bool {
        switch id {
        case .manualQuantity: true
        case .manualTyped: kind == .tracked(.count) || !categories.isEmpty
        case .health: false
        }
    }

    public var supportsOutput: Bool {
        switch id {
        case .manualQuantity: false
        case .manualTyped: kind == .tracked(.count) || !categories.isEmpty
        case .health(let metric, _): metric == .restingHeartRate || metric == .sleepAnalysis
        }
    }

    public var categories: [TrackingCategory] {
        if case .tracked(.category(let options)) = kind { return options }
        return []
    }

    var unit: String {
        switch kind {
        case .quantity(let unit): unit
        case .tracked(.count): "count"
        case .tracked: ""
        }
    }
}

extension HealthAnalysisApplication {
    @MainActor public var analysisVariables: [AnalysisVariable] {
        [
            .init(id: .health(metric: .restingHeartRate), name: "Resting heart rate", kind: .quantity(unit: "bpm")),
            .init(id: .health(metric: .sleepAnalysis), name: "Sleep duration", kind: .quantity(unit: "h"))
        ] + manualAnalysisSeries.map(\.variable)
    }

    @MainActor var manualAnalysisSeries: [ManualAnalysisSeries] {
        manualLog.quantities.map(ManualAnalysisSeries.quantity)
            + manualLog.typedVariables.map(ManualAnalysisSeries.typed)
    }
}

enum ManualAnalysisSeries {
    struct Sample {
        let value: Double?
        let origin: ManualValueOrigin
        var trackingValue: ManualTrackingValue? = nil
    }

    case quantity(TrackingQuantity)
    case typed(TypedTrackingVariable)

    var variable: AnalysisVariable {
        switch self {
        case .quantity(let quantity):
            .init(id: .manualQuantity(quantity.id), name: quantity.name, kind: .quantity(unit: quantity.unit))
        case .typed(let tracked):
            .init(id: .manualTyped(tracked.id), name: tracked.name, kind: .tracked(tracked.kind))
        }
    }

    @MainActor func numericValue(
        in log: ManualLog, on day: ManualLogDay, category: CategoryAnalysis.Transform? = nil
    ) -> Sample? {
        switch self {
        case .quantity(let quantity):
            guard let (amount, origin) = log.analysisValue(for: quantity, on: day) else { return nil }
            let value = NSDecimalNumber(decimal: amount).doubleValue
            guard value.isFinite, quantity.unit.lowercased() != "mg" || value >= 0 else { return nil }
            return Sample(value: value, origin: origin)
        case .typed(let variable):
            guard let (value, origin) = log.analysisValue(for: variable, on: day) else { return nil }
            switch value {
            case .count(let count) where variable.kind == .count && count >= 0:
                return Sample(value: Double(count), origin: origin, trackingValue: value)
            case .category(let id) where !self.variable.categories.isEmpty:
                guard let category else { return nil }
                return Sample(value: category.encode(id), origin: origin, trackingValue: value)
            default:
                return nil
            }
        }
    }

    @MainActor func firstDay(in log: ManualLog) -> ManualLogDay? {
        guard case .typed(let variable) = self else { return nil }
        return log.typedDefaults(variable.id).first?.effectiveOn
    }
}
