import Foundation
import HealthAnalysisCore
import Testing

@Test func openingLogResetsTheSelectedDayToToday() {
    let yesterday = Date(timeIntervalSince1970: 1_700_000_000)
    let today = yesterday.addingTimeInterval(86_400)
    let zone = TimeZone.gmt
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var session = HealthAnalysisSession(storeURL: url, today: yesterday, timeZone: zone)
    #expect(session.tab == .analysis)
    session.selectTab(.log, today: yesterday, timeZone: zone)
    session.selectLogDay(LogDay(yesterday, timeZone: zone))
    session.selectTab(.analysis, today: today, timeZone: zone)
    session.selectTab(.log, today: today, timeZone: zone)
    #expect(session.logDay == LogDay(today, timeZone: zone))
}
