import Foundation

public struct LogDay: Codable, Comparable, Hashable {
    private let year: Int
    private let month: Int
    private let day: Int

    public init(_ date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year!
        month = components.month!
        day = components.day!
    }

    public func date(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public struct LogQuantity: Codable, Identifiable {
    public let id: UUID
    public internal(set) var name: String
    public internal(set) var unit: String
    let defaultValue: Decimal
    let effectiveDay: LogDay
    var trackingStart: LogDay?
    public internal(set) var endDay: LogDay?
    var defaultChanges: [LogDay: Decimal]?

    public var startDay: LogDay { trackingStart ?? effectiveDay }

    func tracks(_ day: LogDay) -> Bool {
        day >= startDay && (endDay.map { day <= $0 } ?? true)
    }

    public var latestDefaultDay: LogDay {
        defaultChanges?.keys.max().map { max($0, effectiveDay) } ?? effectiveDay
    }

    var latestDefaultValue: Decimal {
        applicableDefault(on: latestDefaultDay) ?? defaultValue
    }

    func applicableDefault(on day: LogDay) -> Decimal? {
        let latest = defaultChanges?.keys.filter { $0 <= day }.max()
        if let latest, latest >= effectiveDay || day < effectiveDay {
            return defaultChanges?[latest]
        }
        return day >= effectiveDay ? defaultValue : nil
    }
}

public enum QuantitySettingsError: Error, Equatable {
    case missingName, missingUnit, invalidDefault, invalidTrackingPeriod, rangeExcludesEntries, saveFailed
    case earlierDefaultRequiresConfirmation
    case endDateWouldRemoveEntries(Int)
}

public enum LogEditFeedback: Equatable {
    case invalidNumber, saveFailed
}

public enum LogDayStatus: Equatable {
    case unmarked, editsSaved, confirmed
}

public struct LogDayConfirmation {
    public let canSave: Bool
    public let saveFailed: Bool
}

public struct LogQuantityObservation: Equatable {
    public enum Origin: Equatable {
        case recorded, confirmedDefault
    }

    public let value: Decimal
    public let origin: Origin

    public init(value: Decimal, origin: Origin) {
        self.value = value
        self.origin = origin
    }
}

public struct LogQuantityField: Identifiable {
    public let quantity: LogQuantity
    public let assumedDefault: String?
    public let savedValue: String?
    public let observationOrigin: LogQuantityObservation.Origin?
    public let feedback: LogEditFeedback?
    public var id: UUID { quantity.id }
}

struct DailyLog: Codable {
    var quantities: [LogQuantity] = []
    var entries: [LogDay: [UUID: Decimal]] = [:]
    var confirmedDays: [LogDay: [UUID: Decimal]]?

    static func open(at url: URL) throws -> Self {
        do {
            var log = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            for index in log.quantities.indices where log.quantities[index].trackingStart == nil {
                let quantity = log.quantities[index]
                let firstEntry = log.recordedDays(for: quantity.id).min() ?? quantity.effectiveDay
                log.quantities[index].trackingStart = min(firstEntry, quantity.effectiveDay)
            }
            return log
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Self()
        }
    }

    func recordedDays(for id: UUID) -> [LogDay] {
        let edited = entries.compactMap { day, quantities in quantities[id] == nil ? nil : day }
        let defaulted = confirmedDays?.compactMap { day, quantities in quantities[id] == nil ? nil : day } ?? []
        return Array(Set(edited).union(defaulted))
    }

    mutating func removeEntries(for id: UUID, on days: [LogDay]) {
        for day in days {
            entries[day]?[id] = nil
            if entries[day]?.isEmpty == true { entries[day] = nil }
            confirmedDays?[day]?[id] = nil
        }
    }

    func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

struct QuantityNumberFormat {
    private let locale: Locale
    private let decimalSeparator: String
    private let groupingSeparator: String?
    private let groupingSize: Int
    private let secondaryGroupingSize: Int
    private let signs: [(prefix: String, normalized: String)]

    init(locale: Locale) {
        self.locale = locale
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        decimalSeparator = formatter.decimalSeparator ?? "."
        groupingSeparator = formatter.groupingSeparator
        groupingSize = formatter.groupingSize
        secondaryGroupingSize = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : groupingSize
        signs = [(formatter.minusSign ?? "-", "-"), (formatter.plusSign ?? "+", "+"), ("−", "-"), ("-", "-"), ("+", "+")]
    }

    func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sign = signs.first { trimmed.hasPrefix($0.prefix) }
        let unsigned = String(trimmed.dropFirst(sign?.prefix.count ?? 0))
        let parts = unsigned.components(separatedBy: decimalSeparator)
        guard parts.count <= 2, let last = parts.last, !last.isEmpty else { return nil }

        let fraction = parts.count == 2 ? parts[1] : ""
        guard let whole = normalizeWholePart(parts[0]), let fraction = normalizeDigits(fraction) else { return nil }
        let significantDigits = (whole + fraction).drop(while: { $0 == "0" }).reversed().drop(while: { $0 == "0" })
        guard significantDigits.count <= 38 else { return nil }
        let normalized = (sign?.normalized ?? "") + whole + (fraction.isEmpty ? "" : "." + fraction)
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func normalizeWholePart(_ text: String) -> String? {
        let groups = groupingSeparator.map { text.components(separatedBy: $0) } ?? [text]
        if groups.count > 1 {
            let leadingCount = groups[0].count
            guard groupingSize > 0,
                  leadingCount > 0, leadingCount <= secondaryGroupingSize,
                  groups.last?.count == groupingSize,
                  groups.dropFirst().dropLast().allSatisfy({ $0.count == secondaryGroupingSize }) else { return nil }
        }
        return normalizeDigits(groups.joined())
    }

    private func normalizeDigits(_ text: String) -> String? {
        var normalized = ""
        for scalar in text.unicodeScalars {
            guard scalar.properties.numericType == .decimal,
                  let digit = Character(String(scalar)).wholeNumberValue else { return nil }
            normalized += String(digit)
        }
        return normalized
    }

    func format(_ value: Decimal) -> String {
        var value = value
        return NSDecimalString(&value, locale)
    }
}
