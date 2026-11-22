import HealthAnalysisCore
import SwiftUI

extension AnalysisVariable {
    var analysisChoiceLabel: Text {
        kind.choiceLabel(name: name)
    }
}

extension AnalysisModeledInput {
    var choiceLabel: Text {
        (kind ?? .quantity(unit: unit)).choiceLabel(name: name)
    }

    func displayedValue(_ value: Double, trackingValue: ManualTrackingValue?) -> Text {
        if isClock { return analysisClockText(value) }
        if case .yesNo(let isYes)? = trackingValue { return yesNoLabel(isYes) }
        if case .rating(let level)? = trackingValue { return Text(level, format: .number) }
        return Text("\(value, format: .number) \(unit)")
    }
}

private extension AnalysisVariable.Kind {
    func choiceLabel(name: String) -> Text {
        switch self {
        case .quantity(let unit): Text("\(name) (\(unit))")
        case .tracked(.yesNo): Text("\(name) (yes/no)")
        case .tracked(.count): Text("\(name) (count)")
        case .tracked(.timeOfDay): Text("\(name) (time of day)")
        case .tracked(.rating(let levels)):
            Text("\(name) (rating \(levels.lowerBound, format: .number) to \(levels.upperBound, format: .number))")
        case .tracked: Text(verbatim: name)
        }
    }
}

func yesNoLabel(_ isYes: Bool) -> Text {
    Text(isYes ? "Yes" : "No")
}
