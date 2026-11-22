import HealthAnalysisCore
import SwiftUI

@main
struct HealthAnalysisApp: App {
    private let application: HealthAnalysisApplication = {
        #if DEBUG
        if let fixture = DiscoveryUIFixture.applicationForLaunch() {
            return fixture
        }
        if let fixture = CountAnalysisUIFixture.applicationForLaunch() {
            return fixture
        }
        if let fixture = ExploreAnalysisUIFixture.applicationForLaunch() {
            return fixture
        }
        #endif
        let health = healthConfiguration()
        return HealthAnalysisApplication(
            healthSource: health.source,
            healthHistoryStoreURL: health.storeURL,
            manualLogStoreURL: ManualLogStoreLocation.url,
            savedAnalysesStoreURL: URL.applicationSupportDirectory
                .appending(path: "SavedAnalyses", directoryHint: .isDirectory)
                .appending(path: "questions.json", directoryHint: .notDirectory)
        )
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
            ContentView(application: application)
        }
    }
}
