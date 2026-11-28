import Foundation

public struct HealthAnalysisSession {
    public enum Tab: Hashable {
        case analysis, log
    }

    private struct FieldKey: Hashable {
        let day: LogDay
        let variableID: UUID
    }

    private struct Draft {
        enum Content {
            case text(String)
            case value(LogValue)
        }

        let content: Content
        let feedback: LogEditFeedback?

        var text: String? {
            if case .text(let text) = content { return text }
            return nil
        }

        var value: LogValue? {
            if case .value(let value) = content { return value }
            return nil
        }
    }

    private struct PendingDayReview {
        var assumedValues: [UUID: Decimal] = [:]
        var typedDefaults: [UUID: LogValue] = [:]
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
            drafts = drafts.filter { $0.key.variableID != id || $0.key.day <= endDay }
        }
    }

    public mutating func removeQuantity(_ id: UUID) throws(QuantitySettingsError) {
        guard var updated = log, let index = updated.quantities.firstIndex(where: { $0.id == id }) else { throw .saveFailed }
        updated.quantities.remove(at: index)
        let recordedDays = updated.recordedDays(for: id)
        updated.removeEntries(for: id, on: recordedDays)
        try saveQuantitySettings(updated)
        drafts = drafts.filter { $0.key.variableID != id }
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
            let draft = drafts[FieldKey(day: day, variableID: quantity.id)]
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
        drafts[FieldKey(day: day, variableID: id)]?.text
            ?? observation(for: id, on: day).map { quantityFormat.format($0.value) } ?? ""
    }

    public mutating func editQuantity(_ id: UUID, on day: LogDay, text: String) {
        guard var updated = log,
              updated.quantities.contains(where: { $0.id == id && $0.tracks(day) }) else { return }
        let key = FieldKey(day: day, variableID: id)
        guard let value = quantityFormat.parse(text) else {
            drafts[key] = Draft(content: .text(text), feedback: .invalidNumber)
            return
        }

        do {
            if updated.entries[day]?[id] != value {
                updated.entries[day, default: [:]][id] = value
                updated.confirmedDays?[day]?[id] = nil
                try persist(updated)
            }
            drafts[key] = Draft(content: .text(text), feedback: nil)
        } catch {
            drafts[key] = Draft(content: .text(text), feedback: .saveFailed)
        }
    }

    public mutating func retryQuantity(_ id: UUID, on day: LogDay) {
        guard let draft = drafts[FieldKey(day: day, variableID: id)],
              draft.feedback == .saveFailed, let text = draft.text else { return }
        editQuantity(id, on: day, text: text)
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
        log?.entries[day]?.isEmpty == false || log?.typed?.entries[day]?.isEmpty == false
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
        if !review.typedDefaults.isEmpty {
            updated.typed?.confirmedDefaults[day, default: [:]].merge(review.typedDefaults) { existing, _ in existing }
        }
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
            if drafts[FieldKey(day: day, variableID: quantity.id)]?.feedback != nil {
                review.hasUnresolvedDraft = true
            }
            if observation(for: quantity.id, on: day) == nil {
                review.assumedValues[quantity.id] = quantity.applicableDefault(on: day)
            }
        }
        for variable in logVariables where day >= variable.startDay {
            if drafts[FieldKey(day: day, variableID: variable.id)]?.feedback != nil {
                review.hasUnresolvedDraft = true
            }
            if typedObservation(for: variable.id, on: day) == nil {
                review.typedDefaults[variable.id] = variable.applicableDefault(on: day)
            }
        }
        let hasDefaults = !review.assumedValues.isEmpty || !review.typedDefaults.isEmpty
        return hasDefaults || logStatus(on: day) == .editsSaved ? review : nil
    }

    private mutating func persist(_ updated: DailyLog) throws {
        try updated.save(to: storeURL)
        log = updated
        failedDayConfirmations = failedDayConfirmations.filter { pendingDayReview(on: $0) != nil }
    }
}

extension HealthAnalysisSession {
    public var logVariables: [LogVariable] { log?.typed?.variables ?? [] }

    @discardableResult
    public mutating func createLogVariable(
        name: String,
        kind: LogVariable.Kind,
        defaultValue: LogValue? = nil,
        startDay: LogDay
    ) throws(LogVariableSettingsError) -> LogVariable {
        guard let log else { throw .saveFailed }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .missingName }
        let kind = try kind.validated()
        if let defaultValue, !kind.accepts(defaultValue) { throw .invalidDefault }

        var typed = log.typed ?? TypedLog()
        let variable = LogVariable(id: UUID(), name: name, kind: kind, startDay: startDay, defaultValue: defaultValue)
        typed.variables.append(variable)
        try saveTypedSettings(typed)
        return variable
    }

    public mutating func changeLogDefault(
        _ id: UUID,
        to value: LogValue?,
        effectiveDay: LogDay,
        applyToEarlierDays: Bool = false,
        today: LogDay = LogDay(.now, timeZone: .autoupdatingCurrent)
    ) throws(LogVariableSettingsError) {
        guard var typed = log?.typed, let index = typed.variables.firstIndex(where: { $0.id == id }) else { throw .saveFailed }
        let variable = typed.variables[index]
        if let value, !variable.kind.accepts(value) { throw .invalidDefault }
        guard effectiveDay >= variable.startDay else { throw .defaultBeforeTracking }
        guard effectiveDay >= today || applyToEarlierDays else { throw .earlierDefaultRequiresConfirmation }

        var defaults = variable.defaultChanges ?? [:]
        defaults[effectiveDay] = LogVariable.DefaultChange(value: value)
        typed.variables[index].defaultChanges = defaults
        try saveTypedSettings(typed)
    }

    private mutating func saveTypedSettings(_ typed: TypedLog) throws(LogVariableSettingsError) {
        guard var updated = log else { throw .saveFailed }
        updated.typed = typed
        do {
            try persist(updated)
        } catch {
            throw .saveFailed
        }
    }

    public func typedLogFields(on day: LogDay) -> [TypedLogField] {
        logVariables.compactMap { variable in
            guard day >= variable.startDay else { return nil }
            let observation = typedObservation(for: variable.id, on: day)
            let draft = drafts[FieldKey(day: day, variableID: variable.id)]
            return TypedLogField(
                variable: variable,
                assumedDefault: observation == nil ? variable.applicableDefault(on: day) : nil,
                observation: observation,
                pendingValue: draft?.value,
                feedback: draft?.feedback
            )
        }
    }

    public func typedObservation(for id: UUID, on day: LogDay) -> LogObservation<LogValue>? {
        log?.typed?.observation(for: id, on: day)
    }

    public func parseCount(_ text: String) -> Int? {
        quantityFormat.parseCount(text)
    }

    public func formatCount(_ count: Int) -> String {
        quantityFormat.formatCount(count)
    }

    public func countText(_ id: UUID, on day: LogDay) -> String {
        if let text = drafts[FieldKey(day: day, variableID: id)]?.text { return text }
        if case .count(let count) = typedObservation(for: id, on: day)?.value {
            return formatCount(count)
        }
        return ""
    }

    public mutating func editCount(_ id: UUID, on day: LogDay, text: String) {
        guard let variable = logVariables.first(where: { $0.id == id }), day >= variable.startDay,
              case .count = variable.kind else { return }
        let key = FieldKey(day: day, variableID: id)
        guard let count = parseCount(text) else {
            drafts[key] = Draft(content: .text(text), feedback: .invalidNumber)
            return
        }
        saveTypedEdit(.count(count), for: key, draft: .text(text))
    }

    public mutating func editTypedValue(_ id: UUID, on day: LogDay, value: LogValue) {
        guard let variable = logVariables.first(where: { $0.id == id }), day >= variable.startDay,
              variable.kind.accepts(value) else { return }
        let key = FieldKey(day: day, variableID: id)
        saveTypedEdit(value, for: key, draft: .value(value))
    }

    public mutating func retryTypedEdit(_ id: UUID, on day: LogDay) {
        guard let draft = drafts[FieldKey(day: day, variableID: id)], draft.feedback == .saveFailed else { return }
        switch draft.content {
        case .text(let text): editCount(id, on: day, text: text)
        case .value(let value): editTypedValue(id, on: day, value: value)
        }
    }

    private mutating func saveTypedEdit(_ value: LogValue, for key: FieldKey, draft: Draft.Content) {
        guard var updated = log, var typed = updated.typed else { return }
        do {
            if typed.entries[key.day]?[key.variableID] != value {
                typed.entries[key.day, default: [:]][key.variableID] = value
                typed.confirmedDefaults[key.day]?[key.variableID] = nil
                updated.typed = typed
                try persist(updated)
            }
            if case .text = draft {
                drafts[key] = Draft(content: draft, feedback: nil)
            } else {
                drafts[key] = nil
            }
        } catch {
            drafts[key] = Draft(content: draft, feedback: .saveFailed)
        }
    }
}
