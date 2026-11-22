import Foundation

public enum QuantityNumber {
    public static func parse(_ text: String, locale: Locale) -> Decimal? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)[...]
        let formatter = NumberFormatter()
        formatter.locale = locale
        let signs = [(formatter.minusSign ?? "-", "-"), (formatter.plusSign ?? "+", "+"), ("-", "-"), ("+", "+")]
        var normalized = ""
        if let (sign, ascii) = signs.first(where: { body.hasPrefix($0.0) }) {
            body.removeFirst(sign.count)
            normalized += ascii
        }

        let parts = body.components(separatedBy: locale.decimalSeparator ?? ".")
        guard parts.count <= 2, let last = parts.last, !last.isEmpty else { return nil }

        for (index, part) in parts.enumerated() {
            if index > 0 { normalized += "." }
            for scalar in part.unicodeScalars {
                guard scalar.properties.numericType == .decimal, let digit = scalar.properties.numericValue else { return nil }
                normalized += String(Int(digit))
            }
        }
        let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
        guard let value, !value.isNaN else { return nil }
        return value
    }

    public static func format(_ value: Decimal, locale: Locale) -> String {
        value.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...128)))
    }
}
