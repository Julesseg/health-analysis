import Foundation

enum BinaryEvent {
    static let minimumSupport = 6

    static func encode(_ isYes: Bool) -> Double { isYes ? 1 : 0 }

    static func hasSupport(_ values: [Double], minimum: Int = minimumSupport) -> Bool {
        values.count(where: { $0 == 0 }) >= minimum && values.count(where: { $0 == 1 }) >= minimum
    }
}

struct BinaryEventFit {
    struct Comparison {
        let rowIndex: Int
        let lower: Double
        let upper: Double
    }

    private let rows: [[Double]]
    private let centers: [Double]
    private let scales: [Double]
    private let coefficients: [Double]
    private let residuals: [Double]
    private let information: WeightedDesignInformation

    init?(columns: [[Double]], events: [Double]) {
        guard !columns.isEmpty, events.count > columns.count + 1,
              columns.allSatisfy({ $0.count == events.count }),
              events.allSatisfy({ $0 == 0 || $0 == 1 }) else { return nil }
        let eventRate = events.reduce(0, +) / Double(events.count)
        guard eventRate > 0, eventRate < 1 else { return nil }
        let centers = columns.map { $0.reduce(0, +) / Double($0.count) }
        let centered = zip(columns, centers).map { column, center in column.map { $0 - center } }
        let scales = centered.map { $0.map(abs).max() ?? 0 }
        guard scales.allSatisfy({ $0 > 0 && $0.isFinite }) else { return nil }
        let rows = events.indices.map { row in
            [1.0] + centered.indices.map { centered[$0][row] / scales[$0] }
        }

        var coefficients = [log(eventRate / (1 - eventRate))] + columns.map { _ in 0.0 }
        guard var iteration = Iteration(rows: rows, events: events, coefficients: coefficients) else { return nil }
        for _ in 0..<60 {
            guard let information = WeightedDesignInformation(rows: rows, weights: iteration.weights) else { return nil }
            let score = coefficients.indices.map { column in
                rows.indices.reduce(0.0) { $0 + rows[$1][column] * iteration.residuals[$1] }
            }
            let step = information.solve(score)
            let maximumChange = rows.map { abs(innerProduct($0, step)) }.max() ?? .infinity
            guard maximumChange.isFinite else { return nil }
            if maximumChange < 1e-7 {
                self.rows = rows
                self.centers = centers
                self.scales = scales
                self.coefficients = coefficients
                self.residuals = iteration.residuals
                self.information = information
                return
            }
            var size = 1.0
            var improved = false
            for _ in 0..<24 {
                let candidate = zip(coefficients, step).map { $0 + size * $1 }
                if let next = Iteration(rows: rows, events: events, coefficients: candidate),
                   next.loss <= iteration.loss + 1e-12 * max(1, iteration.loss) {
                    coefficients = candidate
                    iteration = next
                    improved = true
                    break
                }
                size *= 0.5
            }
            guard improved else { return nil }
        }
        return nil
    }

    func probabilityDifference(
        varying column: Int, comparisons: [Comparison], dayNumbers: [Int], lagDays: Int
    ) -> (difference: Double, interval: ClosedRange<Double>)? {
        guard !comparisons.isEmpty else { return nil }
        let count = Double(comparisons.count)
        let designColumn = column + 1
        var difference = 0.0
        var gradient = coefficients.map { _ in 0.0 }
        for comparison in comparisons {
            var low = rows[comparison.rowIndex]
            var high = low
            low[designColumn] = (comparison.lower - centers[column]) / scales[column]
            high[designColumn] = (comparison.upper - centers[column]) / scales[column]
            let lowProbability = Self.probability(innerProduct(low, coefficients))
            let highProbability = Self.probability(innerProduct(high, coefficients))
            difference += highProbability - lowProbability
            for parameter in gradient.indices {
                gradient[parameter] += high[parameter] * highProbability * (1 - highProbability)
                    - low[parameter] * lowProbability * (1 - lowProbability)
            }
        }
        difference /= count
        let influence = information.solve(gradient.map { $0 / count })
        let scores = zip(rows, residuals).map { innerProduct($0, influence) * $1 }
        let halfWidth = CalendarHAC.halfWidth(
            scores: scores, dayNumbers: dayNumbers, lagDays: lagDays, parameterCount: coefficients.count
        )
        guard halfWidth > 0, (abs(difference) + halfWidth).isFinite else { return nil }
        return (difference, max(-1, difference - halfWidth)...min(1, difference + halfWidth))
    }

    private static func probability(_ predictor: Double) -> Double {
        if predictor < 0 {
            let odds = exp(predictor)
            return odds / (1 + odds)
        }
        return 1 / (1 + exp(-predictor))
    }

    private struct Iteration {
        let residuals: [Double]
        let weights: [Double]
        let loss: Double

        init?(rows: [[Double]], events: [Double], coefficients: [Double]) {
            let predictors = rows.map { innerProduct($0, coefficients) }
            guard predictors.allSatisfy({ abs($0) <= 30 }) else { return nil }
            let means = predictors.map(BinaryEventFit.probability)
            residuals = zip(events, means).map(-)
            weights = means.map { $0 * (1 - $0) }
            loss = zip(events, predictors).reduce(0) { sum, pair in
                let (event, predictor) = pair
                return sum + (event == 1 ? max(0, -predictor) : max(0, predictor)) + log1p(exp(-abs(predictor)))
            }
        }
    }
}

private func innerProduct(_ lhs: [Double], _ rhs: [Double]) -> Double {
    zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
}
