import Foundation

enum DiscoveryBlockEvidence {
    static let blockCount = 5
    private static let blockDays = DiscoverySearch.historyDays / blockCount
    private static let washoutDays = 7

    struct Assessment {
        let mean: Double
        let pValue: Double
        let directionsAgree: Bool
    }

    static func assess(
        _ result: AnalysisResult, startOfHistory: Date, calendar: Calendar
    ) -> Assessment? {
        let interaction = result.configuration.interaction
        let inputCount = result.modeledInputs.count
        let columnCount = inputCount + (interaction == nil ? 0 : 1)
        var rowsByBlock = Array(repeating: [AnalysisObservation](), count: blockCount)
        guard let start = dayNumber(startOfHistory, calendar: calendar) else { return nil }
        for row in result.observations {
            guard let day = dayNumber(row.outputDate, calendar: calendar),
                  let anchor = dayNumber(row.outputAnchor, calendar: calendar),
                  let firstBehaviorDate = row.inputs.first?.date,
                  let firstBehaviorDay = dayNumber(firstBehaviorDate, calendar: calendar),
                  row.inputs.allSatisfy({ $0.origin == .observation }) else { continue }
            let block = (day - start) / blockDays
            let blockStart = start + block * blockDays
            guard rowsByBlock.indices.contains(block), anchor < blockStart + blockDays,
                  min(day, anchor, firstBehaviorDay) >= blockStart + washoutDays else { continue }
            rowsByBlock[block].append(row)
        }

        let minimumRows = max(16, 5 * (columnCount + 1))
        var estimates: [Double] = []
        for rows in rowsByBlock {
            guard rows.count >= minimumRows,
                  let estimate = coefficient(
                    rows: rows, inputCount: inputCount, hasInteraction: interaction != nil, calendar: calendar
                  ) else { return nil }
            estimates.append(estimate)
        }
        let count = Double(estimates.count)
        let mean = estimates.reduce(0, +) / count
        let standardError = sqrt(estimates.reduce(0) { $0 + pow($1 - mean, 2) } / (count * (count - 1)))
        guard standardError > 0, standardError.isFinite, mean.isFinite else { return nil }
        let hypotenuse = hypot(mean, 2 * standardError)
        let x = abs(mean) / hypotenuse
        let tail = pow(2 * standardError / hypotenuse, 2) / (1 + x)
        // Two-sided Student t tail for the four degrees of freedom of this fixed design.
        return Assessment(
            mean: mean, pValue: tail * tail * (x + 2) / 2,
            directionsAgree: estimates.allSatisfy { $0 != 0 && $0.sign == mean.sign }
        )
    }

    private static func coefficient(
        rows: [AnalysisObservation], inputCount: Int, hasInteraction: Bool, calendar: Calendar
    ) -> Double? {
        var columns = (0..<inputCount).map { index in rows.map { $0.inputs[index].value } }
        if hasInteraction {
            let center = columns.map { $0.reduce(0, +) / Double(rows.count) }
            columns.append(zip(columns[0], columns[1]).map { ($0 - center[0]) * ($1 - center[1]) })
        }
        guard let fit = try? LinearAssociationFit(
            columns: columns, outputs: rows.map(\.outputValue),
            dayNumbers: rows.compactMap { dayNumber($0.outputDate, calendar: calendar) }, lagDays: 0
        ), fit.varianceInflation.allSatisfy({ $0 < 20 }) else { return nil }
        var contrast = Array(repeating: 0.0, count: columns.count)
        contrast[hasInteraction ? columns.count - 1 : 0] = 1
        return fit.coefficient(contrast: contrast)
    }

    private static func dayNumber(_ date: Date, calendar: Calendar) -> Int? {
        calendar.ordinality(of: .day, in: .era, for: date)
    }
}
