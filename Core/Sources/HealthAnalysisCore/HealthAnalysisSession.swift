import Foundation

public struct HealthAnalysisSession {
    public enum Tab: Hashable {
        case analysis, log
    }

    private struct FieldKey: Hashable {
        let day: LogDay
        let quantityID: UUID
    }

    private struct Draft {
        let text: String
        let feedback: LogEditFeedback?
    }

    public private(set) var tab: Tab = .analysis
    public private(set) var logDay: LogDay
    private let storeURL: URL
    private let quantityFormat: QuantityNumberFormat
    private var log: DailyLog?
    private var drafts: [FieldKey: Draft] = [:]
    public var isLogAvailable: Bool { log != nil }

    public init(
        storeURL: URL,
        today: Date = .now,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.storeURL = storeURL
        logDay = LogDay(today, timeZone: timeZone)
        quantityFormat = QuantityNumberFormat(locale: locale)
        log = try? DailyLog.open(at: storeURL)
    }

    public mutating func retryOpeningLog() {
        guard log == nil else { return }
        log = try? DailyLog.open(at: storeURL)
    }

    public mutating func selectTab(_ tab: Tab, today: Date = .now, timeZone: TimeZone = .autoupdatingCurrent) {
        if self.tab != tab && tab == .log {
            selectLogDay(LogDay(today, timeZone: timeZone))
        }
        self.tab = tab
    }

    public mutating func selectLogDay(_ day: LogDay) {
        if logDay != day {
            drafts = drafts.filter { $0.value.feedback != nil }
        }
        logDay = day
    }

    @discardableResult
    public mutating func createQuantity(
        name: String,
        unit: String,
        defaultText: String,
        effectiveDay: LogDay
    ) throws(QuantityCreationError) -> LogQuantity {
        guard var updated = log else { throw .saveFailed }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .missingName }
        guard !unit.isEmpty else { throw .missingUnit }
        guard let defaultValue = quantityFormat.parse(defaultText) else { throw .invalidDefault }

        let quantity = LogQuantity(id: UUID(), name: name, unit: unit, defaultValue: defaultValue, effectiveDay: effectiveDay)
        updated.quantities.append(quantity)
        do {
            try persist(updated)
        } catch {
            throw .saveFailed
        }
        return quantity
    }

    public func logFields(on day: LogDay) -> [LogQuantityField] {
        guard let log else { return [] }
        return log.quantities.map { quantity in
            let value = recordedQuantity(quantity.id, on: day)
            let applies = day >= quantity.effectiveDay && value == nil
            let draft = drafts[FieldKey(day: day, quantityID: quantity.id)]
            return LogQuantityField(
                quantity: quantity,
                assumedDefault: applies ? quantityFormat.format(quantity.defaultValue) : nil,
                feedback: draft?.feedback
            )
        }
    }

    public func quantityText(_ id: UUID, on day: LogDay) -> String {
        drafts[FieldKey(day: day, quantityID: id)]?.text ?? recordedQuantity(id, on: day).map(quantityFormat.format) ?? ""
    }

    public mutating func editQuantity(_ id: UUID, on day: LogDay, text: String) {
        guard var updated = log, updated.quantities.contains(where: { $0.id == id }) else { return }
        let key = FieldKey(day: day, quantityID: id)
        guard let value = quantityFormat.parse(text) else {
            drafts[key] = Draft(text: text, feedback: .invalidNumber)
            return
        }

        do {
            if recordedQuantity(id, on: day) != value {
                updated.entries[day, default: [:]][id] = value
                try persist(updated)
            }
            drafts[key] = Draft(text: text, feedback: nil)
        } catch {
            drafts[key] = Draft(text: text, feedback: .saveFailed)
        }
    }

    public mutating func retryQuantity(_ id: UUID, on day: LogDay) {
        guard let draft = drafts[FieldKey(day: day, quantityID: id)], draft.feedback == .saveFailed else { return }
        editQuantity(id, on: day, text: draft.text)
    }

    public func recordedQuantity(_ id: UUID, on day: LogDay) -> Decimal? {
        log?.entries[day]?[id]
    }

    public func hasSavedEdits(on day: LogDay) -> Bool {
        log?.entries[day]?.isEmpty == false
    }

    private mutating func persist(_ updated: DailyLog) throws {
        try updated.save(to: storeURL)
        log = updated
    }
}
