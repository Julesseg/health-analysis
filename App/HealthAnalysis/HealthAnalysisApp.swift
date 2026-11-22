import HealthAnalysisCore
import SwiftUI

@main
struct HealthAnalysisApp: App {
    private let application = HealthAnalysisApplication()

    var body: some Scene {
        WindowGroup {
            ContentView(application: application)
        }
    }
}
