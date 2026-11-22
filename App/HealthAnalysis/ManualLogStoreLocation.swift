import Foundation

enum ManualLogStoreLocation {
    static var url: URL {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_MANUAL_LOG_TEST_STORE"],
           let id = UUID(uuidString: value) {
            return URL.temporaryDirectory
                .appending(path: "ManualLogUITests", directoryHint: .isDirectory)
                .appending(path: id.uuidString, directoryHint: .isDirectory)
                .appending(path: "manual-log.json", directoryHint: .notDirectory)
        }
        #endif
        return URL.applicationSupportDirectory.appending(path: "manual-log.json", directoryHint: .notDirectory)
    }
}
