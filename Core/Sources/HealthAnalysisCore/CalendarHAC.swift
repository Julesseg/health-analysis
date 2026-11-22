import Foundation

enum CalendarHAC {
    static func defaultLagDays(for count: Int) -> Int {
        max(7, Int(ceil(2 * pow(Double(count), 1.0 / 3.0))))
    }

    static func halfWidth(scores: [Double], dayNumbers: [Int], lagDays: Int, parameterCount: Int) -> Double {
        let count = Double(scores.count)
        let variance = bartlettSum(scores, dayNumbers: dayNumbers, lagDays: lagDays)
            * count / (count - Double(parameterCount))
        let bandwidth = Double(lagDays + 1) / count
        // Bartlett critical value for a two-sided nominal 95% interval.
        let criticalValue = 1.96 + bandwidth * (2.9694 + bandwidth * (0.4160 - 0.5324 * bandwidth))
        return criticalValue * sqrt(variance)
    }

    private static func bartlettSum(_ scores: [Double], dayNumbers: [Int], lagDays: Int) -> Double {
        var sum = scores.reduce(0) { $0 + $1 * $1 }
        for index in scores.indices.dropFirst() {
            for prior in (0..<index).reversed() {
                let lag = dayNumbers[index] - dayNumbers[prior]
                if lag > lagDays { break }
                let weight = 1 - Double(lag) / Double(lagDays + 1)
                sum += 2 * weight * scores[index] * scores[prior]
            }
        }
        return sum
    }
}
