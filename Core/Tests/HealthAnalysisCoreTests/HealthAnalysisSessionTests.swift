import Foundation
import HealthAnalysisCore
import Testing

@Test func reopeningTheDailyLogStartsOnTodayAndPreservesTheTab() {
    let yesterday = Date(timeIntervalSince1970: 1_700_000_000)
    let today = yesterday.addingTimeInterval(86_400)
    var session = HealthAnalysisSession(today: yesterday)
    #expect(session.tab == .insights)
    #expect(session.sheet == nil)

    session.tab = .data
    session.openLog(today: today)
    session.logDate = yesterday
    session.sheet = nil
    #expect(session.tab == .data)

    session.openLog(today: today)
    #expect(session.sheet == .log)
    #expect(session.logDate == today)
    #expect(session.tab == .data)
}

@Test func aFreshLibraryHasNoMeasurementsVariablesOrFindings() {
    let library = HealthAnalysisSession().library
    #expect(library.measurements == 0)
    #expect(library.trackingVariables == 0)
    #expect(library.savedAnalyses == 0)
    #expect(library.discoveries == 0)
    #expect(!library.canExplore)
}
