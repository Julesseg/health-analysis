import Foundation
import HealthAnalysisCore
import Testing

@Test func openingLogResetsTheSelectedDayToToday() {
    let yesterday = Date(timeIntervalSince1970: 1_700_000_000)
    let today = yesterday.addingTimeInterval(86_400)
    var session = HealthAnalysisSession(today: yesterday)
    #expect(session.tab == .analysis)
    session.selectTab(.log, today: yesterday)
    session.logDate = yesterday
    session.selectTab(.analysis, today: today)
    session.selectTab(.log, today: today)
    #expect(session.logDate == today)
}
