import HealthAnalysisCore
import SwiftUI

extension AnalysisVariable {
    var analysisChoiceLabel: Text {
        switch kind {
        case .quantity(let unit): Text("\(name) (\(unit))")
        case .tracked(.count): Text("\(name) (count)")
        case .tracked: Text(name)
        }
    }
}
