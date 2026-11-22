import Foundation
import Observation

public struct ManualLogDay: Codable, Comparable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year!
        month = components.month!
        day = components.day!
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public struct TrackingQuantity: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let unit: String
    public let defaultValue: Decimal
    public let startsOn: ManualLogDay
}

public struct DailyQuantity: Identifiable, Sendable {
    public enum Status: Sendable {
        case assumedDefault
        case saved
        case invalid
        case saveFailed
    }

    public let quantity: TrackingQuantity
    public let recordedValue: Decimal?
    public let text: String
    public let status: Status

    public var id: TrackingQuantity.ID { quantity.id }
    public var value: Decimal { recordedValue ?? quantity.defaultValue }
}

@MainActor @Observable
public final class ManualLog {
    public enum CreationError: Error {
        case invalidQuantity
        case persistenceFailed
    }

    public enum TypedVariableCreationError: Error {
        case invalidDefinition
        case persistenceFailed
    }

    private struct Entry: Codable, Hashable, Sendable {
        let day: ManualLogDay
        let quantityID: TrackingQuantity.ID
    }

    private struct Edit {
        let text: String
        let locale: Locale
        let status: DailyQuantity.Status
    }

    private struct Snapshot: Codable, Sendable {
        var quantities: [TrackingQuantity] = []
        var entries: [Entry: Decimal] = [:]
        var typed: TypedLogSnapshot?

        static func load(from url: URL) throws -> Self {
            do {
                return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return Self()
            }
        }
    }

    private let storeURL: URL?
    private var snapshot: Snapshot?
    private var edits: [Entry: Edit] = [:]
    private var typedEdits: [TypedLogEntryKey: TypedLogEdit] = [:]

    nonisolated init(storeURL: URL?) {
        self.storeURL = storeURL
        _snapshot = try? storeURL.map(Snapshot.load(from:)) ?? Snapshot()
    }

    public var quantities: [TrackingQuantity] { snapshot?.quantities ?? [] }
    public var typedVariables: [TypedTrackingVariable] { snapshot?.typed?.variables ?? [] }
    public var isStoreAvailable: Bool { snapshot != nil }

    @discardableResult
    public func createQuantity(
        name: String, unit: String, defaultValue: Decimal, startsOn: ManualLogDay
    ) throws(CreationError) -> TrackingQuantity {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !unit.isEmpty, !defaultValue.isNaN else {
            throw .invalidQuantity
        }
        guard var updated = snapshot else { throw .persistenceFailed }
        let quantity = TrackingQuantity(id: UUID(), name: name, unit: unit, defaultValue: defaultValue, startsOn: startsOn)
        updated.quantities.append(quantity)

        do {
            try persist(updated)
        } catch {
            throw .persistenceFailed
        }
        return quantity
    }

    public func dailyQuantities(on day: ManualLogDay, locale: Locale) -> [DailyQuantity] {
        quantities.filter { $0.startsOn <= day }.map { quantity in
            dailyQuantity(quantity, on: day, locale: locale)
        }
    }

    public func dailyQuantity(_ id: TrackingQuantity.ID, on day: ManualLogDay, locale: Locale) -> DailyQuantity? {
        guard let quantity = quantities.first(where: { $0.id == id }), day >= quantity.startsOn else { return nil }
        return dailyQuantity(quantity, on: day, locale: locale)
    }

    private func dailyQuantity(_ quantity: TrackingQuantity, on day: ManualLogDay, locale: Locale) -> DailyQuantity {
        let entry = Entry(day: day, quantityID: quantity.id)
        let recordedValue = snapshot?.entries[entry]
        let edit = edits[entry]
        let text = edit.flatMap { $0.status != .saved || $0.locale == locale ? $0.text : nil }
        return DailyQuantity(
            quantity: quantity,
            recordedValue: recordedValue,
            text: text ?? QuantityNumber.format(recordedValue ?? quantity.defaultValue, locale: locale),
            status: edit?.status ?? (recordedValue == nil ? .assumedDefault : .saved)
        )
    }

    public func editQuantity(_ id: TrackingQuantity.ID, on day: ManualLogDay, text: String, locale: Locale) {
        guard let quantity = quantities.first(where: { $0.id == id }), day >= quantity.startsOn,
            var updated = snapshot else { return }
        let entry = Entry(day: day, quantityID: id)
        guard let value = QuantityNumber.parse(text, locale: locale) else {
            edits[entry] = Edit(text: text, locale: locale, status: .invalid)
            return
        }
        updated.entries[entry] = value
        do {
            try persist(updated)
            edits[entry] = Edit(text: text, locale: locale, status: .saved)
        } catch {
            edits[entry] = Edit(text: text, locale: locale, status: .saveFailed)
        }
    }

    public func retryQuantity(_ id: TrackingQuantity.ID, on day: ManualLogDay) {
        let entry = Entry(day: day, quantityID: id)
        guard let edit = edits[entry], edit.status == .saveFailed else { return }
        editQuantity(id, on: day, text: edit.text, locale: edit.locale)
    }

    @discardableResult
    public func createTypedVariable(
        name: String, kind: TrackingVariableKind, defaultValue: ManualTrackingValue, startsOn: ManualLogDay
    ) throws(TypedVariableCreationError) -> TypedTrackingVariable {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, kind.accepts(defaultValue) else { throw .invalidDefinition }
        guard var updated = snapshot else { throw .persistenceFailed }
        let variable = TypedTrackingVariable(
            id: UUID(), name: name, kind: kind, defaultValue: defaultValue, startsOn: startsOn
        )
        var typed = updated.typed ?? TypedLogSnapshot()
        typed.variables.append(variable)
        updated.typed = typed

        do {
            try persist(updated)
        } catch {
            throw .persistenceFailed
        }
        return variable
    }

    public func dailyTypedEntries(on day: ManualLogDay) -> [DailyTypedEntry] {
        typedVariables.filter { $0.startsOn <= day }.map { dailyTypedEntry($0, on: day) }
    }

    public func dailyTypedEntry(_ id: TypedTrackingVariable.ID, on day: ManualLogDay) -> DailyTypedEntry? {
        guard let variable = typedVariables.first(where: { $0.id == id }), day >= variable.startsOn else {
            return nil
        }
        return dailyTypedEntry(variable, on: day)
    }

    private func dailyTypedEntry(_ variable: TypedTrackingVariable, on day: ManualLogDay) -> DailyTypedEntry {
        let key = TypedLogEntryKey(day: day, variableID: variable.id)
        let recordedValue = snapshot?.typed?.entries[key]
        let edit = typedEdits[key]
        return DailyTypedEntry(
            variable: variable,
            day: day,
            recordedValue: recordedValue,
            draftValue: edit?.value,
            status: edit?.status ?? (recordedValue == nil ? .assumedDefault : .saved)
        )
    }

    public func editTypedEntry(_ id: TypedTrackingVariable.ID, on day: ManualLogDay, value: ManualTrackingValue) {
        guard var updated = snapshot, var typed = updated.typed,
            let variable = typed.variables.first(where: { $0.id == id }), day >= variable.startsOn else { return }
        let key = TypedLogEntryKey(day: day, variableID: id)
        guard variable.kind.accepts(value) else {
            typedEdits[key] = TypedLogEdit(value: value, status: .invalid)
            return
        }
        typed.entries[key] = value
        updated.typed = typed
        do {
            try persist(updated)
            typedEdits[key] = nil
        } catch {
            typedEdits[key] = TypedLogEdit(value: value, status: .saveFailed)
        }
    }

    public func retryTypedEntry(_ id: TypedTrackingVariable.ID, on day: ManualLogDay) {
        let key = TypedLogEntryKey(day: day, variableID: id)
        guard let edit = typedEdits[key], edit.status == .saveFailed else { return }
        editTypedEntry(id, on: day, value: edit.value)
    }

    private func persist(_ updated: Snapshot) throws {
        if let storeURL {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: storeURL, options: .atomic)
        }
        snapshot = updated
    }
}
