import Foundation

struct PoissonMeanFit {
    private let rows: [[Double]]
    private let scales: [Double]
    private let coefficients: [Double]
    private let residuals: [Double]
    private let information: CountInformation
    private let hasResidualVariation: Bool
    private static let convergenceTolerance = 1e-7

    init?(columns: [[Double]], counts: [Double]) {
        guard !columns.isEmpty, counts.count > columns.count + 1,
              columns.allSatisfy({ $0.count == counts.count }),
              counts.allSatisfy({ $0 >= 0 && $0.isFinite }) else { return nil }
        let mean = counts.reduce(0, +) / Double(counts.count)
        guard mean > 0, mean.isFinite else { return nil }
        let centered = columns.map { column in
            let center = column.reduce(0, +) / Double(column.count)
            return column.map { $0 - center }
        }
        let scales = centered.map { $0.map(abs).max() ?? 0 }
        guard scales.allSatisfy({ $0 > 0 && $0.isFinite }) else { return nil }
        let rows = counts.indices.map { row in
            [1.0] + centered.indices.map { centered[$0][row] / scales[$0] }
        }
        var coefficients = [log(mean)] + columns.map { _ in 0.0 }
        for _ in 0..<60 {
            guard let fit = Iteration(rows: rows, counts: counts, coefficients: coefficients),
                  let information = CountInformation(rows: rows, means: fit.means) else { return nil }
            let score = coefficients.indices.map { column in
                rows.indices.reduce(0.0) { $0 + rows[$1][column] * fit.residuals[$1] }
            }
            let step = information.solve(score)
            let maxChange = rows.map { abs(innerProduct($0, step)) }.max() ?? .infinity
            guard maxChange.isFinite else { return nil }
            if maxChange < Self.convergenceTolerance {
                self.rows = rows
                self.scales = scales
                self.coefficients = coefficients
                self.residuals = fit.residuals
                self.information = information
                self.hasResidualVariation = zip(fit.means, fit.residuals).contains { mean, residual in
                    abs(residual) > Self.convergenceTolerance * max(1, mean)
                }
                return
            }
            guard let next = Self.improvingStep(
                from: coefficients, step: step, loss: fit.loss, rows: rows, counts: counts
            ) else { return nil }
            coefficients = next
        }
        return nil
    }

    func logContrast(
        _ contrast: [Double], dayNumbers: [Int], lagDays: Int
    ) -> (estimate: Double, halfWidth: Double)? {
        guard hasResidualVariation, contrast.count == scales.count, dayNumbers.count == rows.count else { return nil }
        let weights = [0.0] + zip(contrast, scales).map(/)
        let estimate = innerProduct(weights, coefficients)
        let influence = information.solve(weights)
        let scores = zip(rows, residuals).map { innerProduct($0, influence) * $1 }
        let halfWidth = CalendarHAC.halfWidth(
            scores: scores, dayNumbers: dayNumbers, lagDays: lagDays, parameterCount: coefficients.count
        )
        guard halfWidth > 0, (abs(estimate) + halfWidth).isFinite else { return nil }
        return (estimate, halfWidth)
    }

    private static func improvingStep(
        from coefficients: [Double], step: [Double], loss: Double, rows: [[Double]], counts: [Double]
    ) -> [Double]? {
        var size = 1.0
        for _ in 0..<24 {
            let candidate = zip(coefficients, step).map { $0 + size * $1 }
            if let fit = Iteration(rows: rows, counts: counts, coefficients: candidate),
               fit.loss <= loss + 1e-12 * max(1, abs(loss)) {
                return candidate
            }
            size *= 0.5
        }
        return nil
    }

    private struct Iteration {
        let means: [Double]
        let residuals: [Double]
        let loss: Double

        init?(rows: [[Double]], counts: [Double], coefficients: [Double]) {
            let predictors = rows.map { innerProduct($0, coefficients) }
            guard predictors.allSatisfy({ (-35...50).contains($0) }) else { return nil }
            let means = predictors.map { exp($0) }
            self.means = means
            residuals = zip(counts, means).map(-)
            loss = means.reduce(0, +) - innerProduct(counts, predictors)
        }
    }
}

private struct CountInformation {
    let lower: [[Double]]

    init?(rows: [[Double]], means: [Double]) {
        guard let size = rows.first?.count else { return nil }
        let total = means.reduce(0, +)
        var lower = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        for row in 0..<size {
            for column in 0...row {
                var value = rows.indices.reduce(0.0) { sum, index in
                    sum + means[index] * rows[index][row] * rows[index][column]
                }
                for prior in 0..<column {
                    value -= lower[row][prior] * lower[column][prior]
                }
                if row == column {
                    guard value > total * 1e-12, value.isFinite else { return nil }
                    lower[row][column] = sqrt(value)
                } else {
                    lower[row][column] = value / lower[column][column]
                }
            }
        }
        self.lower = lower
    }

    func solve(_ target: [Double]) -> [Double] {
        var solution = target
        for row in lower.indices {
            for column in 0..<row {
                solution[row] -= lower[row][column] * solution[column]
            }
            solution[row] /= lower[row][row]
        }
        for row in lower.indices.reversed() {
            for column in (row + 1)..<lower.count {
                solution[row] -= lower[column][row] * solution[column]
            }
            solution[row] /= lower[row][row]
        }
        return solution
    }
}

private func innerProduct(_ lhs: [Double], _ rhs: [Double]) -> Double {
    zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
}
