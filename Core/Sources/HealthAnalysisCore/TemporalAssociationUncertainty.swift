import Foundation

enum TemporalAssociationUncertainty {
    static func assess(
        scores: [Double], residuals: [Double], dayNumbers: [Int], windowDays: Int, parameterCount: Int
    ) -> (scoreHalfWidth: Double, lagDays: Int) {
        let count = scores.count
        let baselineLag = max(windowDays - 1, CalendarHAC.defaultLagDays(for: count))
        func scoreHalfWidth(at lag: Int) -> Double {
            CalendarHAC.halfWidth(
                scores: scores, dayNumbers: dayNumbers, lagDays: lag, parameterCount: parameterCount
            )
        }
        let baselineWidth = scoreHalfWidth(at: baselineLag)
        guard hasSerialDependence(residuals, dayNumbers: dayNumbers) else {
            return (baselineWidth, baselineLag)
        }
        let lagLimit = max(baselineLag, count / 2 - 1)
        let mediumLag = min(lagLimit, max(baselineLag, 14, 2 * windowDays))
        let longLag = min(lagLimit, max(baselineLag, 21, 3 * windowDays, count / 4))
        return (1.2 * max(baselineWidth, scoreHalfWidth(at: mediumLag), scoreHalfWidth(at: longLag)), longLag)
    }

    private static func hasSerialDependence(_ residuals: [Double], dayNumbers: [Int]) -> Bool {
        let residualByDay = Dictionary(uniqueKeysWithValues: zip(dayNumbers, residuals))
        return [1, 2, 3, 7, 14, 30].contains { lag in
            var products = 0.0
            var priorSquares = 0.0
            var currentSquares = 0.0
            var pairs = 0
            for (day, residual) in zip(dayNumbers, residuals) {
                guard let prior = residualByDay[day - lag] else { continue }
                products += prior * residual
                priorSquares += prior * prior
                currentSquares += residual * residual
                pairs += 1
            }
            guard pairs >= 20, priorSquares > 0, currentSquares > 0 else { return false }
            let correlation = abs(products) / (sqrt(priorSquares) * sqrt(currentSquares))
            return correlation > max(0.2, 3 / sqrt(Double(pairs)))
        }
    }
}
