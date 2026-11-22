import Foundation

struct BernoulliLogitFit {
    private let rows: [[Double]]
    private let scales: [Double]
    private let coefficients: [Double]
    private let residuals: [Double]
    private let information: WeightedDesignInformation

    init?(columns: [[Double]], events: [Double]) {
        guard !columns.isEmpty, events.count > columns.count + 1,
              columns.allSatisfy({ $0.count == events.count }),
              events.allSatisfy({ $0 == 0 || $0 == 1 }) else { return nil }
        let rate = events.reduce(0, +) / Double(events.count)
        guard rate > 0, rate < 1 else { return nil }
        let centered = columns.map { column in
            let mean = column.reduce(0, +) / Double(column.count)
            return column.map { $0 - mean }
        }
        let scales = centered.map { $0.map(abs).max() ?? 0 }
        guard scales.allSatisfy({ $0 > 0 && $0.isFinite }) else { return nil }
        let rows = events.indices.map { row in
            [1.0] + centered.indices.map { centered[$0][row] / scales[$0] }
        }
        var coefficients = [log(rate / (1 - rate))] + columns.map { _ in 0.0 }
        for _ in 0..<60 {
            guard let iteration = Iteration(rows: rows, events: events, coefficients: coefficients),
                  let information = WeightedDesignInformation(rows: rows, weights: iteration.weights) else { return nil }
            let score = coefficients.indices.map { column in
                rows.indices.reduce(0.0) { $0 + rows[$1][column] * iteration.residuals[$1] }
            }
            let step = information.solve(score)
            let maxChange = rows.map { abs(dot($0, step)) }.max() ?? .infinity
            guard maxChange.isFinite else { return nil }
            if maxChange < 1e-7 {
                self.rows = rows
                self.scales = scales
                self.coefficients = coefficients
                self.residuals = iteration.residuals
                self.information = information
                return
            }
            guard let next = Self.improvingStep(
                from: coefficients, step: step, loss: iteration.loss, rows: rows, events: events
            ) else { return nil }
            coefficients = next
        }
        return nil
    }

    func logOddsContrast(
        _ contrast: [Double], dayNumbers: [Int], lagDays: Int
    ) -> (estimate: Double, halfWidth: Double)? {
        guard contrast.count == scales.count, dayNumbers.count == rows.count,
              (0..<rows.count).contains(lagDays),
              zip(dayNumbers, dayNumbers.dropFirst()).allSatisfy(<) else { return nil }
        let weights = [0.0] + zip(contrast, scales).map(/)
        let estimate = dot(weights, coefficients)
        let influence = information.solve(weights)
        let scores = zip(rows, residuals).map { dot($0, influence) * $1 }
        let halfWidth = CalendarHAC.halfWidth(
            scores: scores, dayNumbers: dayNumbers, lagDays: lagDays, parameterCount: coefficients.count
        )
        guard halfWidth > 0, (abs(estimate) + halfWidth).isFinite else { return nil }
        return (estimate, halfWidth)
    }

    private static func improvingStep(
        from coefficients: [Double], step: [Double], loss: Double, rows: [[Double]], events: [Double]
    ) -> [Double]? {
        var size = 1.0
        for _ in 0..<24 {
            let candidate = zip(coefficients, step).map { $0 + size * $1 }
            if let fit = Iteration(rows: rows, events: events, coefficients: candidate),
               fit.loss <= loss + 1e-12 * max(1, loss) {
                return candidate
            }
            size *= 0.5
        }
        return nil
    }

    private struct Iteration {
        let weights: [Double]
        let residuals: [Double]
        let loss: Double

        init?(rows: [[Double]], events: [Double], coefficients: [Double]) {
            let predictors = rows.map { dot($0, coefficients) }
            guard predictors.allSatisfy({ (-30...30).contains($0) }) else { return nil }
            let probabilities = predictors.map { 1 / (1 + exp(-$0)) }
            weights = probabilities.map { $0 * (1 - $0) }
            residuals = zip(events, probabilities).map(-)
            loss = zip(predictors, events).reduce(0.0) { loss, pair in
                let (predictor, event) = pair
                let error = event == 1 ? -predictor : predictor
                return loss + max(0, error) + log1p(exp(-abs(error)))
            }
        }
    }
}

private func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
    zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
}
