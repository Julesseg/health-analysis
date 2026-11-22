import Foundation
import Observation

@MainActor
@Observable
public final class FirstUseSetup {
    public enum Step: Sendable {
        case healthAccess
        case coverage
        case manualTracking
        case complete
    }

    public private(set) var step: Step = .healthAccess
    private let health: HealthMeasurementHistory
    private let storeURL: URL?

    nonisolated init(health: HealthMeasurementHistory, storeURL: URL?) {
        self.health = health
        self.storeURL = storeURL
        if let storeURL, FileManager.default.fileExists(atPath: storeURL.path) {
            _step = .complete
        }
    }

    public func requestHealthAccess() async {
        guard step == .healthAccess || step == .coverage, health.readState != .loading else { return }
        step = .coverage
        await health.requestAccessAndRefresh()
    }

    public func continueWithoutHealthAccess() {
        guard step == .healthAccess else { return }
        step = .coverage
    }

    public func continueToTracking() {
        guard step == .coverage, health.readState != .loading else { return }
        step = .manualTracking
    }

    public func finish() throws {
        guard step == .manualTracking else { return }
        if let storeURL {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data().write(to: storeURL, options: .atomic)
        }
        step = .complete
    }
}
