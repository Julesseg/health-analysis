extension AnalysisVariable.Kind {
    public var ratingThreshold: Int? {
        guard case .tracked(.rating(let levels)) = self, levels.lowerBound < levels.upperBound else { return nil }
        let span = UInt(bitPattern: levels.upperBound) &- UInt(bitPattern: levels.lowerBound)
        return levels.lowerBound + Int(span / 2) + Int(span % 2)
    }
}

enum RatingAnalysis {
    static func indicator(_ value: ManualTrackingValue?, threshold: Int) -> Double? {
        guard case .rating(let level)? = value else { return nil }
        return level >= threshold ? 1 : 0
    }

    static func hasSupport(_ indicators: [Double]) -> Bool {
        indicators.count(where: { $0 == 0 }) >= 6 && indicators.count(where: { $0 == 1 }) >= 6
    }
}
