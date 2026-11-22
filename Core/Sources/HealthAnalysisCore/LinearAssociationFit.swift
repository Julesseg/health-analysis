import Foundation

struct LinearAssociationFit {
    enum Failure: Error {
        case dependentColumns(Set<Int>)
        case unavailable
    }

    private let design: OrthogonalDesign
    private let centeredOutput: [Double]
    private let residuals: [Double]
    private let dayNumbers: [Int]
    private let lagDays: Int
    private let windowDays: Int
    private let hasResidualVariation: Bool

    init(columns: [[Double]], outputs: [Double], dayNumbers: [Int], lagDays: Int, windowDays: Int = 1) throws(Failure) {
        guard !columns.isEmpty, outputs.count > columns.count + 1, dayNumbers.count == outputs.count,
              (0..<outputs.count).contains(lagDays),
              zip(dayNumbers, dayNumbers.dropFirst()).allSatisfy(<),
              columns.allSatisfy({ $0.count == outputs.count }) else { throw .unavailable }
        let design = try OrthogonalDesign(columns: columns)
        let mean = average(outputs)
        let centeredOutput = outputs.map { $0 - mean }
        var residuals = centeredOutput
        for column in design.basis {
            let coefficient = dot(column, residuals)
            for index in outputs.indices {
                residuals[index] -= coefficient * column[index]
            }
        }
        self.design = design
        self.centeredOutput = centeredOutput
        self.residuals = residuals
        self.dayNumbers = dayNumbers
        self.lagDays = lagDays
        self.windowDays = windowDays
        hasResidualVariation = (residuals.map(abs).max() ?? 0) > 64 * Double.ulpOfOne * abs(mean)
    }

    var varianceInflation: [Double] { design.varianceInflation }

    // Weights in the original units, one per supplied design column.
    func estimate(contrast: [Double]) -> (difference: Double, halfWidth: Double, lagDays: Int)? {
        guard contrast.count == design.basis.count, hasResidualVariation else { return nil }
        let weights = design.observationWeights(for: contrast)
        let difference = dot(weights, centeredOutput)
        let scores = zip(weights, residuals).map(*)
        let parameterCount = design.basis.count + 1
        let halfWidth: Double
        let maximumLag: Int
        if windowDays > 1 {
            (halfWidth, maximumLag) = TemporalAssociationUncertainty.assess(
                scores: scores, residuals: residuals, dayNumbers: dayNumbers,
                windowDays: windowDays, parameterCount: parameterCount
            )
        } else {
            halfWidth = CalendarHAC.halfWidth(
                scores: scores, dayNumbers: dayNumbers, lagDays: lagDays, parameterCount: parameterCount
            )
            maximumLag = lagDays
        }
        guard halfWidth > 0, (abs(difference) + halfWidth).isFinite else { return nil }
        return (difference, halfWidth, maximumLag)
    }
}

private struct OrthogonalDesign {
    let basis: [[Double]]
    private let triangular: [[Double]]
    private let scales: [Double]

    init(columns: [[Double]]) throws(LinearAssociationFit.Failure) {
        var basis: [[Double]] = []
        var triangular: [[Double]] = []
        var scales: [Double] = []
        var independent: [Int] = []
        var dependent: Set<Int> = []
        for (columnIndex, column) in columns.enumerated() {
            let mean = average(column)
            var orthogonal = column.map { $0 - mean }
            let scale = sqrt(dot(orthogonal, orthogonal))
            guard scale > 0, scale.isFinite else { throw .unavailable }
            scales.append(scale)
            orthogonal = orthogonal.map { $0 / scale }
            var projections = Array(repeating: 0.0, count: basis.count)
            for _ in 0..<2 {
                for (previous, unit) in basis.enumerated() {
                    let projection = dot(unit, orthogonal)
                    projections[previous] += projection
                    for index in orthogonal.indices {
                        orthogonal[index] -= projection * unit[index]
                    }
                }
            }
            let diagonal = sqrt(dot(orthogonal, orthogonal))
            if diagonal <= 1e-8 {
                dependent.insert(columnIndex)
                // Express the redundant column in the original normalized columns.
                for row in projections.indices.reversed() {
                    let coefficient = projections[row] / triangular[row][row]
                    if abs(coefficient) > 1e-8 { dependent.insert(independent[row]) }
                    for earlier in 0..<row {
                        projections[earlier] -= triangular[row][earlier] * coefficient
                    }
                }
                continue
            }
            basis.append(orthogonal.map { $0 / diagonal })
            triangular.append(projections + [diagonal])
            independent.append(columnIndex)
        }
        guard dependent.isEmpty else { throw .dependentColumns(dependent) }
        self.basis = basis
        self.triangular = triangular
        self.scales = scales
    }

    var varianceInflation: [Double] {
        basis.indices.map { index in
            let unit = basis.indices.map { $0 == index ? 1.0 : 0.0 }
            let dual = solveTransposed(unit)
            return dot(dual, dual)
        }
    }

    func observationWeights(for contrast: [Double]) -> [Double] {
        let dual = solveTransposed(zip(contrast, scales).map(/))
        var weights = Array(repeating: 0.0, count: basis.first?.count ?? 0)
        for (coefficient, column) in zip(dual, basis) {
            for index in weights.indices {
                weights[index] += coefficient * column[index]
            }
        }
        return weights
    }

    private func solveTransposed(_ values: [Double]) -> [Double] {
        var solved: [Double] = []
        for (index, column) in triangular.enumerated() {
            let remainder = values[index] - dot(solved, column)
            solved.append(remainder / column[index])
        }
        return solved
    }
}

private func average(_ values: [Double]) -> Double {
    values.reduce(0, +) / Double(values.count)
}

private func dot(_ first: [Double], _ second: [Double]) -> Double {
    zip(first, second).reduce(0) { $0 + $1.0 * $1.1 }
}
