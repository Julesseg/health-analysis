import HealthAnalysisCore
import SwiftUI

@main
struct HealthAnalysisApp: App {
    @State private var session = HealthAnalysisSession(storeURL: Self.storeURL)

    var body: some Scene {
        WindowGroup {
            ContentView(session: $session)
        }
    }

    private static var storeURL: URL {
        #if DEBUG
        if let identifier = ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_UI_TEST_STORE"],
           let id = UUID(uuidString: identifier) {
            return URL.temporaryDirectory.appending(path: "DailyLog-\(id.uuidString).json")
        }
        #endif
        return URL.applicationSupportDirectory.appending(path: "DailyLog.json")
    }
}
