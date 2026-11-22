public struct ManualDefaultVersion<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let effectiveOn: ManualLogDay
    public let value: Value
}

public enum ManualDefaultScope: Sendable {
    case effectiveDate
    case olderHistory
}

extension ManualLog {
    public enum DefaultError: Error {
        case unknownQuantity
        case invalidValue
        case olderHistoryRequiresOptIn
        case dateMustPrecedeHistory
        case persistenceFailed
    }
}

struct ManualDefaultHistory<Value: Codable & Equatable & Sendable>: Codable, Sendable {
    private(set) var versions: [ManualDefaultVersion<Value>]

    init(initial: ManualDefaultVersion<Value>) {
        versions = [initial]
    }

    func effective(on day: ManualLogDay) -> ManualDefaultVersion<Value>? {
        versions.last { $0.effectiveOn <= day }
    }

    mutating func set(
        _ version: ManualDefaultVersion<Value>, scope: ManualDefaultScope
    ) throws(ManualLog.DefaultError) {
        if let first = versions.first {
            let predatesHistory = version.effectiveOn < first.effectiveOn
            switch scope {
            case .effectiveDate:
                guard !predatesHistory else { throw .olderHistoryRequiresOptIn }
            case .olderHistory:
                guard predatesHistory else { throw .dateMustPrecedeHistory }
            }
        }
        versions.removeAll { $0.effectiveOn == version.effectiveOn }
        versions.append(version)
        versions.sort { $0.effectiveOn < $1.effectiveOn }
    }
}
