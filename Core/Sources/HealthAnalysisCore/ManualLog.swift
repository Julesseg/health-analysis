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
    public let origin: ManualValueOrigin

    public var id: TrackingQuantity.ID { quantity.id }
    public let value: Decimal
}

@MainActor @Observable
public final class ManualLog {
    public enum CreationError: Error {
        case invalidQuantity
        case persistenceFailed
    }

    public enum ReviewError: Error {
        case noFields
        case unresolvedEdits
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
        var defaultHistories: [TrackingQuantity.ID: ManualDefaultHistory<Decimal>]?
        var reviews: [ManualLogDay: ReviewedDay<Decimal>]?

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

    nonisolated init(storeURL: URL?) {
        self.storeURL = storeURL
        _snapshot = try? storeURL.map(Snapshot.load(from:)) ?? Snapshot()
    }

    public var quantities: [TrackingQuantity] { snapshot?.quantities ?? [] }
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

    public func quantityDefaults(_ id: TrackingQuantity.ID) -> [ManualDefaultVersion<Decimal>] {
        guard let quantity = quantities.first(where: { $0.id == id }) else { return [] }
        return defaultHistory(for: quantity).versions
    }

    public func setQuantityDefault(
        _ id: TrackingQuantity.ID, value: Decimal, effectiveOn: ManualLogDay,
        scope: ManualDefaultScope = .effectiveDate
    ) throws(DefaultError) {
        guard var updated = snapshot else { throw .persistenceFailed }
        guard let quantity = updated.quantities.first(where: { $0.id == id }) else { throw .unknownQuantity }
        guard !value.isNaN else { throw .invalidValue }

        var history = defaultHistory(for: quantity)
        try history.set(ManualDefaultVersion(effectiveOn: effectiveOn, value: value), scope: scope)
        updated.defaultHistories = updated.defaultHistories ?? [:]
        updated.defaultHistories?[id] = history

        do {
            try persist(updated)
        } catch {
            throw .persistenceFailed
        }
    }

    private func defaultHistory(for quantity: TrackingQuantity) -> ManualDefaultHistory<Decimal> {
        snapshot?.defaultHistories?[quantity.id] ?? ManualDefaultHistory(
            initial: ManualDefaultVersion(effectiveOn: quantity.startsOn, value: quantity.defaultValue)
        )
    }

    public func dailyQuantities(on day: ManualLogDay, locale: Locale) -> [DailyQuantity] {
        quantities.compactMap { quantity in
            dailyQuantity(quantity, on: day, locale: locale)
        }
    }

    public func dailyQuantity(_ id: TrackingQuantity.ID, on day: ManualLogDay, locale: Locale) -> DailyQuantity? {
        guard let quantity = quantities.first(where: { $0.id == id }) else { return nil }
        return dailyQuantity(quantity, on: day, locale: locale)
    }

    private func dailyQuantity(_ quantity: TrackingQuantity, on day: ManualLogDay, locale: Locale) -> DailyQuantity? {
        guard let field = reviewField(for: quantity, on: day) else { return nil }
        let entry = Entry(day: day, quantityID: quantity.id)
        let recordedValue = field.origin == .observation ? field.value : nil
        let edit = edits[entry]
        let text = edit.flatMap { $0.status != .saved || $0.locale == locale ? $0.text : nil }
        return DailyQuantity(
            quantity: quantity,
            recordedValue: recordedValue,
            text: text ?? QuantityNumber.format(field.value, locale: locale),
            status: edit?.status ?? (recordedValue == nil ? .assumedDefault : .saved),
            origin: field.origin,
            value: field.value
        )
    }

    public func review(on day: ManualLogDay) -> DayReview? {
        snapshot?.reviews?[day]?.status(for: reviewFields(on: day), hasUnresolvedEdits: hasUnresolvedEdits(on: day))
    }

    public func canConfirmDay(_ day: ManualLogDay) -> Bool {
        !hasUnresolvedEdits(on: day) && quantities.contains { reviewField(for: $0, on: day) != nil }
    }

    public func confirmDay(_ day: ManualLogDay) throws(ReviewError) {
        guard var updated = snapshot else { throw .persistenceFailed }
        let fields = reviewFields(on: day)
        guard !fields.isEmpty else { throw .noFields }
        guard !hasUnresolvedEdits(on: day) else { throw .unresolvedEdits }
        var reviews = updated.reviews ?? [:]
        reviews[day] = ReviewedDay(reviewedAt: .now, fields: fields)
        updated.reviews = reviews

        do {
            try persist(updated)
        } catch {
            throw .persistenceFailed
        }
    }

    private func hasUnresolvedEdits(on day: ManualLogDay) -> Bool {
        edits.contains { $0.key.day == day && $0.value.status != .saved }
    }

    private func reviewFields(on day: ManualLogDay) -> [UUID: ReviewField<Decimal>] {
        Dictionary(uniqueKeysWithValues: quantities.compactMap { quantity in
            reviewField(for: quantity, on: day).map { (quantity.id, $0) }
        })
    }

    private func reviewField(for quantity: TrackingQuantity, on day: ManualLogDay) -> ReviewField<Decimal>? {
        ReviewField.resolve(
            observation: snapshot?.entries[Entry(day: day, quantityID: quantity.id)],
            previousReview: snapshot?.reviews?[day]?.fields[quantity.id],
            effectiveDefault: defaultHistory(for: quantity).effective(on: day)
        )
    }

    public func editQuantity(_ id: TrackingQuantity.ID, on day: ManualLogDay, text: String, locale: Locale) {
        guard let quantity = quantities.first(where: { $0.id == id }), reviewField(for: quantity, on: day) != nil,
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

    private func persist(_ updated: Snapshot) throws {
        if let storeURL {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: storeURL, options: .atomic)
        }
        snapshot = updated
    }
}
