import Foundation

enum TemporalAssociationUncertainty {
    static func assess(
        scores: [Double], residuals: [Double], dayNumbers: [Int], windowDays: Int, degreesOfFreedom: Int
    ) -> (scoreHalfWidth: Double, lagDays: Int) {
        let count = scores.count
        let baselineLag = max(7, windowDays - 1, Int(ceil(2 * pow(Double(count), 1.0 / 3.0))))
        let correction = Double(count) / Double(degreesOfFreedom)
        func scoreHalfWidth(at lag: Int) -> Double {
            let bandwidth = Double(lag + 1) / Double(count)
            let criticalValue = 1.96 + bandwidth * (2.9694 + bandwidth * (0.4160 - 0.5324 * bandwidth))
            return criticalValue * sqrt(correction * bartlettSum(scores, dayNumbers: dayNumbers, lag: lag))
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

    private static func bartlettSum(_ scores: [Double], dayNumbers: [Int], lag: Int) -> Double {
        // Two scores share lag + 1 - distance terms in the sum of squared rolling scores.
        var entered = 0
        var expired = 0
        var day = dayNumbers[0]
        var rolling = 0.0
        var sum = 0.0
        while expired < scores.count {
            let start = entered < scores.count ? dayNumbers[entered] : Int.max
            let end = dayNumbers[expired] + lag + 1
            let next = min(start, end)
            sum += Double(next - day) * rolling * rolling
            if next == end {
                rolling -= scores[expired]
                expired += 1
            }
            if next == start {
                rolling += scores[entered]
                entered += 1
            }
            day = next
        }
        return sum / Double(lag + 1)
    }
}
