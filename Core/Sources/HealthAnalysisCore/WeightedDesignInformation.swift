import Foundation

struct WeightedDesignInformation {
    let lower: [[Double]]

    init?(rows: [[Double]], weights: [Double]) {
        guard let size = rows.first?.count else { return nil }
        let total = weights.reduce(0, +)
        var lower = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        for row in 0..<size {
            for column in 0...row {
                var value = rows.indices.reduce(0.0) { sum, index in
                    sum + weights[index] * rows[index][row] * rows[index][column]
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
