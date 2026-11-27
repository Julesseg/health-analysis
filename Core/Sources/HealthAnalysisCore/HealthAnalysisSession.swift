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

    private struct PendingDayReview {
        var assumedValues: [UUID: Decimal] = [:]
        var hasUnresolvedDraft = false
    }

    public private(set) var tab: Tab = .analysis
    public private(set) var logDay: LogDay
    private let storeURL: URL
    private let quantityFormat: QuantityNumberFormat
    private var log: DailyLog?
    private var drafts: [FieldKey: Draft] = [:]
    private var failedDayConfirmations: Set<LogDay> = []
    public var isLogAvailable: Bool { log != nil }
    public var quantities: [LogQuantity] { log?.quantities ?? [] }

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
    ) throws(QuantitySettingsError) -> LogQuantity {
        guard var updated = log else { throw .saveFailed }
        let (name, unit) = try quantityLabels(name: name, unit: unit)
        guard let defaultValue = quantityFormat.parse(defaultText) else { throw .invalidDefault }

        let quantity = LogQuantity(
            id: UUID(), name: name, unit: unit, defaultValue: defaultValue, effectiveDay: effectiveDay, trackingStart: effectiveDay
        )
        updated.quantities.append(quantity)
        try saveQuantitySettings(updated)
        return quantity
    }

    public mutating func updateQuantity(
        _ id: UUID,
        name: String,
        unit: String,
        startDay: LogDay,
        endDay: LogDay?,
        defaultChange: (text: String, effectiveDay: LogDay)? = nil,
        applyDefaultToEarlierDays: Bool = false,
        removeEntriesAfterEnd: Bool = false,
        today: LogDay = LogDay(.now, timeZone: .autoupdatingCurrent)
    ) throws(QuantitySettingsError) {
        guard var updated = log, let index = updated.quantities.firstIndex(where: { $0.id == id }) else { throw .saveFailed }
        let (name, unit) = try quantityLabels(name: name, unit: unit)
        if let endDay, endDay < startDay { throw .invalidTrackingPeriod }
        var quantity = updated.quantities[index]
        quantity.name = name
        quantity.unit = unit
        quantity.trackingStart = startDay
        quantity.endDay = endDay
        let recordedDays = updated.recordedDays(for: id)
        guard !recordedDays.contains(where: { $0 < startDay }) else { throw .rangeExcludesEntries }
        if let defaultChange {
            guard let value = quantityFormat.parse(defaultChange.text) else { throw .invalidDefault }
            guard defaultChange.effectiveDay >= today || applyDefaultToEarlierDays else {
                throw .earlierDefaultRequiresConfirmation
            }
            var changes = quantity.defaultChanges ?? [:]
            changes[defaultChange.effectiveDay] = value
            quantity.defaultChanges = changes
        }
        let excludedDays = endDay.map { end in recordedDays.filter { $0 > end } } ?? []
        if !excludedDays.isEmpty && !removeEntriesAfterEnd { throw .endDateWouldRemoveEntries(excludedDays.count) }
        updated.removeEntries(for: id, on: excludedDays)
        updated.quantities[index] = quantity
        try saveQuantitySettings(updated)
        if removeEntriesAfterEnd, let endDay {
            drafts = drafts.filter { $0.key.quantityID != id || $0.key.day <= endDay }
        }
    }

    public mutating func removeQuantity(_ id: UUID) throws(QuantitySettingsError) {
        guard var updated = log, let index = updated.quantities.firstIndex(where: { $0.id == id }) else { throw .saveFailed }
        updated.quantities.remove(at: index)
        let recordedDays = updated.recordedDays(for: id)
        updated.removeEntries(for: id, on: recordedDays)
        try saveQuantitySettings(updated)
        drafts = drafts.filter { $0.key.quantityID != id }
    }

    public func latestDefaultText(for quantity: LogQuantity) -> String {
        quantityFormat.format(quantity.latestDefaultValue)
    }

    private func quantityLabels(name: String, unit: String) throws(QuantitySettingsError) -> (String, String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .missingName }
        guard !unit.isEmpty else { throw .missingUnit }
        return (name, unit)
    }

    private mutating func saveQuantitySettings(_ updated: DailyLog) throws(QuantitySettingsError) {
        do {
            try persist(updated)
        } catch {
            throw .saveFailed
        }
    }

    public func logFields(on day: LogDay) -> [LogQuantityField] {
        quantities.compactMap { quantity in
            guard quantity.tracks(day) else { return nil }
            let observation = observation(for: quantity.id, on: day)
            let assumed = observation == nil ? quantity.applicableDefault(on: day) : nil
            let draft = drafts[FieldKey(day: day, quantityID: quantity.id)]
            return LogQuantityField(
                quantity: quantity,
                assumedDefault: assumed.map(quantityFormat.format),
                savedValue: observation.map { quantityFormat.format($0.value) },
                observationOrigin: observation?.origin,
                feedback: draft?.feedback
            )
        }
    }

    public func quantityText(_ id: UUID, on day: LogDay) -> String {
        drafts[FieldKey(day: day, quantityID: id)]?.text
            ?? observation(for: id, on: day).map { quantityFormat.format($0.value) } ?? ""
    }

    public mutating func editQuantity(_ id: UUID, on day: LogDay, text: String) {
        guard var updated = log,
              updated.quantities.contains(where: { $0.id == id && $0.tracks(day) }) else { return }
        let key = FieldKey(day: day, quantityID: id)
        guard let value = quantityFormat.parse(text) else {
            drafts[key] = Draft(text: text, feedback: .invalidNumber)
            return
        }

        do {
            if updated.entries[day]?[id] != value {
                updated.entries[day, default: [:]][id] = value
                updated.confirmedDays?[day]?[id] = nil
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

    public func observation(for id: UUID, on day: LogDay) -> LogQuantityObservation? {
        if let value = recordedQuantity(id, on: day) {
            return LogQuantityObservation(value: value, origin: .recorded)
        }
        if let value = log?.confirmedDays?[day]?[id] {
            return LogQuantityObservation(value: value, origin: .confirmedDefault)
        }
        return nil
    }

    public func hasSavedEdits(on day: LogDay) -> Bool {
        log?.entries[day]?.isEmpty == false
    }

    public func logStatus(on day: LogDay) -> LogDayStatus {
        if log?.confirmedDays?[day] != nil { return .confirmed }
        return hasSavedEdits(on: day) ? .editsSaved : .unmarked
    }

    public func dayConfirmation(on day: LogDay) -> LogDayConfirmation? {
        guard let review = pendingDayReview(on: day) else { return nil }
        return LogDayConfirmation(
            canSave: !review.hasUnresolvedDraft,
            saveFailed: failedDayConfirmations.contains(day)
        )
    }

    public mutating func confirmDay(_ day: LogDay) {
        guard var updated = log, let review = pendingDayReview(on: day), !review.hasUnresolvedDraft else { return }
        var reviews = updated.confirmedDays ?? [:]
        reviews[day, default: [:]].merge(review.assumedValues) { existing, _ in existing }
        updated.confirmedDays = reviews
        do {
            try persist(updated)
            failedDayConfirmations.remove(day)
        } catch {
            failedDayConfirmations.insert(day)
        }
    }

    private func pendingDayReview(on day: LogDay) -> PendingDayReview? {
        var review = PendingDayReview()
        for quantity in quantities where quantity.tracks(day) {
            if drafts[FieldKey(day: day, quantityID: quantity.id)]?.feedback != nil {
                review.hasUnresolvedDraft = true
            }
            if observation(for: quantity.id, on: day) == nil {
                review.assumedValues[quantity.id] = quantity.applicableDefault(on: day)
            }
        }
        return review.assumedValues.isEmpty && logStatus(on: day) != .editsSaved ? nil : review
    }

    private mutating func persist(_ updated: DailyLog) throws {
        try updated.save(to: storeURL)
        log = updated
        failedDayConfirmations = failedDayConfirmations.filter { pendingDayReview(on: $0) != nil }
    }
}
