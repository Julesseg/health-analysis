import Foundation

public enum TrackingVariableKind: Codable, Equatable, Sendable {
    case count
    case yesNo
    case rating(ClosedRange<Int>)
    case category([TrackingCategory])
    case timeOfDay

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
        case (.timeOfDay, .timeOfDay(let time, _)):
            (0..<24).contains(time.hour) && (0..<60).contains(time.minute)
        default:
            false
        }
    }

    func acceptsDefault(_ value: ManualTrackingValue) -> Bool {
        if case .timeOfDay(_, .some) = value { return false }
        return accepts(value)
    }
}

public enum ManualTrackingValue: Codable, Equatable, Sendable {
    case count(Int)
    case yesNo(Bool)
    case rating(Int)
    case category(TrackingCategory.ID)
    case timeOfDay(ManualClockTime, precision: ManualClockPrecision? = nil)

    var asObservation: Self {
        if case .timeOfDay(let time, nil) = self { return .timeOfDay(time, precision: .exact) }
        return self
    }
}

public struct ManualClockTime: Codable, Equatable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
}

public enum ManualClockPrecision: String, Codable, Equatable, Sendable {
    case exact
    case approximate
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
