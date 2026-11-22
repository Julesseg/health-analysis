import HealthAnalysisCore
import SwiftUI

@main
struct HealthAnalysisApp: App {
    @UIApplicationDelegateAdaptor private var lifecycle: HealthRefreshLifecycle
    @Environment(\.scenePhase) private var scenePhase

    struct Configuration {
        let application: HealthAnalysisApplication
        var observedSource: HealthKitMeasurementSource? = nil
        var checksOnActivation = false
    }

    static let configuration: Configuration = {
        #if DEBUG
        if let fixture = FirstUseUIFixture.applicationForLaunch() {
            return Configuration(application: fixture)
        }
        if let fixture = DiscoveryUIFixture.applicationForLaunch() {
            return Configuration(application: fixture, checksOnActivation: DiscoveryUIFixture.checksOnActivation)
        }
        if let fixture = BinaryAnalysisUIFixture.applicationForLaunch() {
            return Configuration(application: fixture)
        }
        if let fixture = CountAnalysisUIFixture.applicationForLaunch() {
            return Configuration(application: fixture)
        }
        if let fixture = ExploreAnalysisUIFixture.applicationForLaunch() {
            return Configuration(application: fixture)
        }
        #endif
        let health = healthConfiguration()
        let application = HealthAnalysisApplication(
            healthSource: health.source,
            healthHistoryStoreURL: health.storeURL,
            manualLogStoreURL: ManualLogStoreLocation.url,
            savedAnalysesStoreURL: URL.applicationSupportDirectory
                .appending(path: "SavedAnalyses", directoryHint: .isDirectory)
                .appending(path: "questions.json", directoryHint: .notDirectory),
            firstUseStoreURL: URL.applicationSupportDirectory
                .appending(path: "first-use-complete", directoryHint: .notDirectory)
        )
        let source = health.source as? HealthKitMeasurementSource
        return Configuration(application: application, observedSource: source, checksOnActivation: source != nil)
    }()

    private static func healthConfiguration() -> (source: any HealthMeasurementSource, storeURL: URL) {
        #if DEBUG
        if let fixture = HealthMeasurementUIFixture.configurationForLaunch() {
            return fixture
        }
        #endif
        let url = URL.applicationSupportDirectory
            .appending(path: "HealthHistory", directoryHint: .isDirectory)
            .appending(path: "measurements.json", directoryHint: .notDirectory)
        return (HealthKitMeasurementSource(), url)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(application: Self.configuration.application)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    lifecycle.scenePhaseChanged(phase)
                }
        }
    }
}
