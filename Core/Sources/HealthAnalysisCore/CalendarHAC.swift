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
        // Two scores share lagDays + 1 - distance terms in the sum of squared rolling scores.
        var entered = 0
        var expired = 0
        var day = dayNumbers[0]
        var rolling = 0.0
        var sum = 0.0
        while expired < scores.count {
            let start = entered < scores.count ? dayNumbers[entered] : Int.max
            let end = dayNumbers[expired] + lagDays + 1
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
        return sum / Double(lagDays + 1)
    }
}
