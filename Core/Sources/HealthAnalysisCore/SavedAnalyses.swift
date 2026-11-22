import Foundation
import Observation

public struct SavedAnalysis: Codable, Identifiable, Sendable {
    public let id: UUID
    public let configuration: AnalysisConfiguration
}

@MainActor
@Observable
public final class SavedAnalyses {
    public enum SaveFailure: Error {
        case missingQuestion
        case persistence
    }

    private struct CachedCompletion: Codable, Sendable {
        let value: CompletedAnalysis?

        init(_ value: CompletedAnalysis) {
            self.value = value
        }

        init(from decoder: any Decoder) throws {
            value = try? decoder.singleValueContainer().decode(CompletedAnalysis.self)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }

    private struct Snapshot: Codable, Sendable {
        var questions: [SavedAnalysis] = []
        var pinnedIDs: [SavedAnalysis.ID] = []
        var completions: [SavedAnalysis.ID: CachedCompletion]?
        var discoveryBaselines: [SavedAnalysis.ID: CachedCompletion]?

        mutating func preserveDiscovery(for id: SavedAnalysis.ID) {
            guard discoveryBaselines?[id] == nil, let completion = completions?[id],
                  completion.value?.discovery != nil else { return }
            if discoveryBaselines == nil { discoveryBaselines = [:] }
            discoveryBaselines?[id] = completion
        }

        mutating func store(_ completed: CompletedAnalysis, for id: SavedAnalysis.ID) {
            if completions == nil { completions = [:] }
            completions?[id] = CachedCompletion(completed)
        }

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
    private var refreshRequests: [SavedAnalysis.ID: UUID] = [:]
    private var refreshFailures: [SavedAnalysis.ID: AnalysisRefreshFailure] = [:]

    nonisolated init(storeURL: URL?) {
        self.storeURL = storeURL
        _snapshot = try? storeURL.map(Snapshot.load(from:)) ?? Snapshot()
    }

    public var isStoreAvailable: Bool { snapshot != nil }

    public func reloadIfUnavailable() {
        guard snapshot == nil else { return }
        snapshot = try? writableSnapshot()
    }

    public var questions: [SavedAnalysis] { snapshot?.questions ?? [] }
    public var following: [SavedAnalysis] { (snapshot?.pinnedIDs ?? []).compactMap { question(id: $0) } }

    public func question(id: SavedAnalysis.ID) -> SavedAnalysis? {
        questions.first { $0.id == id }
    }

    public func isPinned(_ id: SavedAnalysis.ID) -> Bool {
        snapshot?.pinnedIDs.contains(id) == true
    }

    public func discoveryBaseline(for id: SavedAnalysis.ID) -> CompletedAnalysis? {
        guard let question = question(id: id) else { return nil }
        let completed = snapshot?.discoveryBaselines?[id]?.value ?? state(for: id).completed
        guard let completed, completed.discovery != nil,
              completed.result.configuration == question.configuration else { return nil }
        return completed
    }

    public func state(for id: SavedAnalysis.ID) -> AnalysisRefreshState {
        let completed = snapshot?.completions?[id]?.value
        let isRefreshing = refreshRequests[id] != nil
        return AnalysisRefreshState(
            completed: completed?.result.configuration == question(id: id)?.configuration ? completed : nil,
            isRefreshing: isRefreshing,
            failure: isRefreshing ? nil : refreshFailures[id]
        )
    }

    @discardableResult
    public func save(
        _ configuration: AnalysisConfiguration,
        updating id: SavedAnalysis.ID? = nil,
        completed: CompletedAnalysis? = nil
    ) throws(SaveFailure) -> SavedAnalysis {
        var updated = try writableSnapshot()
        let question = SavedAnalysis(id: id ?? UUID(), configuration: configuration)
        var configurationChanged = false
        if let id {
            guard let index = updated.questions.firstIndex(where: { $0.id == id }) else {
                throw .missingQuestion
            }
            configurationChanged = updated.questions[index].configuration != configuration
            updated.questions[index] = question
            if configurationChanged {
                updated.completions?[id] = nil
                updated.discoveryBaselines?[id] = nil
            }
        } else {
            updated.questions.append(question)
        }
        let currentUpdate = updated.completions?[question.id]?.value?.updatedAt
        let completionChanged: Bool
        if let completed, completed.result.configuration == configuration,
           currentUpdate.map({ $0 < completed.updatedAt }) ?? true {
            updated.preserveDiscovery(for: question.id)
            updated.store(completed, for: question.id)
            completionChanged = true
        } else {
            completionChanged = false
        }
        try persist(updated)
        if configurationChanged { refreshRequests[question.id] = nil }
        if configurationChanged || completionChanged { refreshFailures[question.id] = nil }
        return question
    }

    public func setPinned(_ pinned: Bool, for id: SavedAnalysis.ID) throws(SaveFailure) {
        var updated = try writableSnapshot()
        guard updated.questions.contains(where: { $0.id == id }) else { throw .missingQuestion }
        guard updated.pinnedIDs.contains(id) != pinned else { return }
        if pinned {
            updated.pinnedIDs.append(id)
        } else {
            updated.pinnedIDs.removeAll { $0 == id }
        }
        try persist(updated)
    }

    func beginRefresh(for id: SavedAnalysis.ID) -> UUID {
        let requestID = UUID()
        refreshRequests[id] = requestID
        return requestID
    }

    func finishRefresh(
        for id: SavedAnalysis.ID,
        requestID: UUID,
        result: Result<CompletedAnalysis, AnalysisRunFailure>?
    ) {
        guard refreshRequests[id] == requestID, var updated = snapshot else { return }
        defer { refreshRequests[id] = nil }
        switch result {
        case .success(let completed):
            do {
                updated.preserveDiscovery(for: id)
                updated.store(completed, for: id)
                try persist(updated)
                refreshFailures[id] = nil
            } catch {
                refreshFailures[id] = .persistence
            }
        case .failure(let failure):
            refreshFailures[id] = .analysis(failure)
        case nil:
            break
        }
    }

    private func writableSnapshot() throws(SaveFailure) -> Snapshot {
        if let snapshot { return snapshot }
        do {
            return try storeURL.map(Snapshot.load(from:)) ?? Snapshot()
        } catch {
            throw .persistence
        }
    }

    private func persist(_ updated: Snapshot) throws(SaveFailure) {
        do {
            if let storeURL {
                let directory = storeURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var options: Data.WritingOptions = .atomic
                #if os(iOS)
                var localDirectory = directory
                var resources = URLResourceValues()
                resources.isExcludedFromBackup = true
                try localDirectory.setResourceValues(resources)
                options.insert(.completeFileProtection)
                #endif
                try JSONEncoder().encode(updated).write(to: storeURL, options: options)
            }
            snapshot = updated
        } catch {
            throw .persistence
        }
    }
}
