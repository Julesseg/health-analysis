import HealthAnalysisCore
import SwiftUI
import UIKit

@MainActor
final class HealthRefreshLifecycle: NSObject, UIApplicationDelegate {
    private nonisolated static let pendingKey = "pendingHealthKitCheck"
    private static let reconciledKey = "reconciledHealthKitCheck"
    private var isForeground = false
    private var pendingForegroundCheck = false
    private var pendingObserverCheck = false
    private var checkTask: Task<Void, Never>?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        HealthAnalysisApp.configuration.observedSource?.observeChanges { [weak self] changed in
            UserDefaults.standard.set(UUID().uuidString, forKey: Self.pendingKey)
            Task { @MainActor in
                if changed { self?.scheduleCheck(observer: true) }
            }
        }
        return true
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        let configuration = HealthAnalysisApp.configuration
        if phase == .active { configuration.application.manualLog.reloadIfUnavailable() }
        guard configuration.checksOnActivation else { return }
        switch phase {
        case .active where !isForeground:
            isForeground = true
            let pending = UserDefaults.standard.string(forKey: Self.pendingKey)
                != UserDefaults.standard.string(forKey: Self.reconciledKey)
            let application = configuration.application
            if pending || application.healthMeasurements.readState != .idle || application.firstUse.step == .complete
                || configuration.observedSource == nil {
                scheduleCheck(observer: pending)
            }
        case .background:
            isForeground = false
            checkTask?.cancel()
        default:
            break
        }
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        HealthAnalysisApp.configuration.application.manualLog.reloadIfUnavailable()
        guard HealthAnalysisApp.configuration.checksOnActivation, checkTask == nil else { return }
        scheduleCheck()
    }

    private func scheduleCheck(observer: Bool = false) {
        pendingForegroundCheck = true
        pendingObserverCheck = pendingObserverCheck || observer
        guard isForeground, checkTask == nil else { return }
        checkTask = Task {
            let history = HealthAnalysisApp.configuration.application.healthMeasurements
            while isForeground, pendingForegroundCheck, !Task.isCancelled {
                let observer = pendingObserverCheck
                let pendingDelivery = UserDefaults.standard.string(forKey: Self.pendingKey)
                pendingForegroundCheck = false
                pendingObserverCheck = false
                if observer {
                    await history.refreshAfterHealthChange()
                } else {
                    await history.refresh()
                }
                if !pendingObserverCheck, history.readState == .loaded, !Task.isCancelled {
                    UserDefaults.standard.set(pendingDelivery, forKey: Self.reconciledKey)
                }
            }
            checkTask = nil
            if isForeground, pendingForegroundCheck { scheduleCheck() }
        }
    }
}
