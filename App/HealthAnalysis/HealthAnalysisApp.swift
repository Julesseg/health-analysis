import HealthAnalysisCore
import SwiftUI

@main
struct HealthAnalysisApp: App {
    private let application = HealthAnalysisApplication(healthSource: HealthAnalysisApp.healthSource())

    private static func healthSource() -> any HealthMeasurementSource {
        #if DEBUG
        if let fixture = HealthMeasurementUIFixture.sourceForLaunch() {
            return fixture
        }
        #endif
        return HealthKitMeasurementSource()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(application: application)
        }
    }
}
