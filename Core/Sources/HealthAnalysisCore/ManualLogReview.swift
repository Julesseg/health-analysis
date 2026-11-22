import Foundation

public enum ManualValueOrigin: Codable, Equatable, Sendable {
    case observation
    case assumedDefault(effectiveOn: ManualLogDay)
}

public struct DayReview: Equatable, Sendable {
    public let reviewedAt: Date
    public let isCurrent: Bool
}

struct ReviewField<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let value: Value
    let origin: ManualValueOrigin

    static func resolve(
        observation: Value?, previousReview: Self?,
        effectiveDefault: @autoclosure () -> ManualDefaultVersion<Value>?
    ) -> Self? {
        if let observation {
            return Self(value: observation, origin: .observation)
        }
        if let previousReview, case .assumedDefault = previousReview.origin {
            return previousReview
        }
        guard let version = effectiveDefault() else { return nil }
        return Self(value: version.value, origin: .assumedDefault(effectiveOn: version.effectiveOn))
    }
}

struct ReviewedDay<Value: Codable & Equatable & Sendable>: Codable, Sendable {
    let reviewedAt: Date
    let fields: [UUID: ReviewField<Value>]

    func status(for currentFields: [UUID: ReviewField<Value>], hasUnresolvedEdits: Bool) -> DayReview {
        DayReview(reviewedAt: reviewedAt, isCurrent: !hasUnresolvedEdits && currentFields == fields)
    }
}
