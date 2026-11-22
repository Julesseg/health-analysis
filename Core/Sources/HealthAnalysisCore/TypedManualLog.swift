import Foundation

public enum TrackingVariableKind: Codable, Equatable, Sendable {
    case count
    case yesNo
    case rating(ClosedRange<Int>)
    case category([TrackingCategory])

    public func accepts(_ value: ManualTrackingValue) -> Bool {
        switch (self, value) {
        case (.count, .count(let count)):
            count >= 0
        case (.yesNo, .yesNo):
            true
        case (.rating(let scale), .rating(let rating)):
            scale.lowerBound < scale.upperBound && scale.contains(rating)
        case (.category(let options), .category(let id)):
            options.count >= 2
                && options.allSatisfy { !$0.name.isEmpty }
                && Set(options.map(\.id)).count == options.count
                && Set(options.map { $0.name.lowercased() }).count == options.count
                && options.contains { $0.id == id }
        default:
            false
        }
    }
}

public enum ManualTrackingValue: Codable, Equatable, Sendable {
    case count(Int)
    case yesNo(Bool)
    case rating(Int)
    case category(TrackingCategory.ID)
}

public struct TrackingCategory: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct TypedTrackingVariable: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let kind: TrackingVariableKind
    public let defaultValue: ManualTrackingValue
    public let startsOn: ManualLogDay
}

public struct DailyTypedEntry: Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case assumedDefault
        case saved
        case invalid
        case saveFailed
    }

    public let variable: TypedTrackingVariable
    public let day: ManualLogDay
    public let recordedValue: ManualTrackingValue?
    public let draftValue: ManualTrackingValue?
    public let status: Status
    public let origin: ManualValueOrigin
    public let value: ManualTrackingValue

    public var id: TypedTrackingVariable.ID { variable.id }
    public var displayedValue: ManualTrackingValue { status == .saveFailed ? draftValue ?? value : value }
}

struct TypedLogEntryKey: Codable, Hashable, Sendable {
    let day: ManualLogDay
    let variableID: TypedTrackingVariable.ID
}

struct TypedLogSnapshot: Codable, Sendable {
    var variables: [TypedTrackingVariable] = []
    var entries: [TypedLogEntryKey: ManualTrackingValue] = [:]
    var defaultHistories: [UUID: ManualDefaultHistory<ManualTrackingValue>]?
}

struct TypedLogEdit {
    let value: ManualTrackingValue
    let status: DailyTypedEntry.Status
}
