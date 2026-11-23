import Foundation

enum ManualLogStoreLocation {
    static var location: (url: URL, legacy: URL?) {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["HEALTH_ANALYSIS_MANUAL_LOG_TEST_STORE"],
           let id = UUID(uuidString: value) {
            let testStore = URL.temporaryDirectory
                .appending(path: "ManualLogUITests", directoryHint: .isDirectory)
                .appending(path: id.uuidString, directoryHint: .isDirectory)
                .appending(path: "manual-log.json", directoryHint: .notDirectory)
            return (testStore, nil)
        }
        #endif
        let support = URL.applicationSupportDirectory
        return (
            support.appending(path: "ManualLog", directoryHint: .isDirectory)
                .appending(path: "manual-log.json", directoryHint: .notDirectory),
            support.appending(path: "manual-log.json", directoryHint: .notDirectory)
        )
    }
}
