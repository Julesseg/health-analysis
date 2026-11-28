import Foundation

public struct LogVariable: Codable, Identifiable {
    public enum Kind: Codable, Equatable {
        case count(unit: String?)
        case yesNo
        case rating([LogOption])
        case category([LogOption])

        public var options: [LogOption] {
            switch self {
            case .rating(let options), .category(let options): options
            case .count, .yesNo: []
            }
        }

        func validated() throws(LogVariableSettingsError) -> Self {
            switch self {
            case .count(let unit):
                let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
                return .count(unit: unit?.isEmpty == false ? unit : nil)
            case .yesNo:
                return self
            case .rating, .category:
                let options = options.map {
                    LogOption(id: $0.id, label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                guard options.count >= 2,
                      options.allSatisfy({ !$0.label.isEmpty }),
                      Set(options.map(\.id)).count == options.count,
                      Set(options.map { $0.label.lowercased() }).count == options.count else { throw .invalidOptions }
                if case .rating = self { return .rating(options) }
                return .category(options)
            }
        }

        func accepts(_ value: LogValue) -> Bool {
            switch (self, value) {
            case (.count, .count(let count)): count >= 0
            case (.yesNo, .yesNo): true
            case (.rating, .option(let id)), (.category, .option(let id)):
                options.contains { $0.id == id }
            default: false
            }
        }
    }

    public let id: UUID
    public let name: String
    public let kind: Kind
    public let startDay: LogDay
    let defaultValue: LogValue?
    var defaultChanges: [LogDay: DefaultChange]?

    struct DefaultChange: Codable {
        let value: LogValue?
    }

    public var latestDefaultDay: LogDay { defaultChanges?.keys.max() ?? startDay }
    public var latestDefaultValue: LogValue? { applicableDefault(on: latestDefaultDay) }

    func applicableDefault(on day: LogDay) -> LogValue? {
        guard day >= startDay else { return nil }
        if let effectiveDay = defaultChanges?.keys.filter({ $0 <= day }).max() {
            return defaultChanges?[effectiveDay]?.value
        }
        return defaultValue
    }
}

public struct LogOption: Codable, Equatable, Identifiable {
    public let id: UUID
    public var label: String

    public init(id: UUID = UUID(), label: String) {
        self.id = id
        self.label = label
    }
}

public enum LogValue: Codable, Equatable, Hashable {
    case count(Int)
    case yesNo(Bool)
    case option(UUID)
}

public enum LogVariableSettingsError: Error, Equatable {
    case missingName, invalidOptions, invalidDefault, saveFailed
    case defaultBeforeTracking, earlierDefaultRequiresConfirmation
}

public struct TypedLogField: Identifiable {
    public let variable: LogVariable
    public let assumedDefault: LogValue?
    public let observation: LogObservation<LogValue>?
    public let pendingValue: LogValue?
    public let feedback: LogEditFeedback?
    public var id: UUID { variable.id }
}

struct TypedLog: Codable {
    var variables: [LogVariable] = []
    var entries: [LogDay: [UUID: LogValue]] = [:]
    var confirmedDefaults: [LogDay: [UUID: LogValue]] = [:]

    func observation(for id: UUID, on day: LogDay) -> LogObservation<LogValue>? {
        if let value = entries[day]?[id] {
            return LogObservation(value: value, origin: .recorded)
        }
        return confirmedDefaults[day]?[id].map { LogObservation(value: $0, origin: .confirmedDefault) }
    }
}
