import HealthAnalysisCore
import SwiftUI

extension AnalysisVariable {
    var analysisChoiceLabel: Text {
        switch kind {
        case .quantity(let unit): Text("\(name) (\(unit))")
        case .tracked(.category): Text("\(name) (category)")
        case .tracked(.yesNo): Text("\(name) (yes/no)")
        case .tracked(.count): Text("\(name) (count)")
        case .tracked: Text(name)
        }
    }
}

extension AnalysisModeledInput {
    var choiceLabel: Text {
        switch kind {
        case .tracked(.count): Text("\(name) (count)")
        case .tracked(.yesNo): Text("\(name) (yes/no)")
        case .tracked(.category): Text("\(name) (category)")
        default: Text("\(name) (\(unit))")
        }
    }

    func analysisValue(_ value: Double, trackingValue: ManualTrackingValue?) -> Text {
        if !categories.isEmpty { return categoryValueLabel(trackingValue, categories: categories) }
        if case .yesNo(let isYes)? = trackingValue { return yesNoLabel(isYes) }
        return Text("\(value, format: .number) \(unit)")
    }
}

func yesNoLabel(_ isYes: Bool) -> Text {
    Text(isYes ? "Yes" : "No")
}
