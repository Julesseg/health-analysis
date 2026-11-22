import HealthAnalysisCore
import SwiftUI

struct SavedAnalysisListSection: View {
    let application: HealthAnalysisApplication
    var followingOnly = false

    private var analyses: SavedAnalyses { application.savedAnalyses }
    private var questions: [SavedAnalysis] { followingOnly ? analyses.following : analyses.questions }

    var body: some View {
        let heading: LocalizedStringKey = followingOnly ? "Following" : "Saved analyses"
        let empty: LocalizedStringKey = followingOnly ? "No followed analyses yet" : "No saved analyses yet"
        Section(heading) {
            if !analyses.isStoreAvailable {
                Text("Couldn’t open saved analyses.")
                Button("Retry") { analyses.reloadIfUnavailable() }
            } else if questions.isEmpty {
                Text(empty)
            } else {
                ForEach(questions) { question in
                    NavigationLink {
                        AnalysisResultScreen(application: application, questionID: question.id)
                    } label: {
                        VStack(alignment: .leading) {
                            title(for: question)
                            if let completed = analyses.state(for: question.id).completed {
                                Text("Updated \(completed.updatedAt, format: .dateTime.month().day().year().hour().minute())")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("savedAnalysis.open")
                }
            }
        }
    }

    private func title(for question: SavedAnalysis) -> Text {
        let configuration = question.configuration
        let output = application.analysisSeriesTitle(configuration.output)
        if configuration.inputs.count > 1 {
            return Text("\(output) with \(configuration.inputs.count) inputs")
        }
        if let input = configuration.inputs.first {
            return Text("\(output) with \(application.analysisSeriesTitle(input))")
        }
        return output
    }
}

extension HealthAnalysisApplication {
    @MainActor func analysisSeriesTitle(_ series: AnalysisSeriesID) -> Text {
        switch series {
        case .manualQuantity(let id):
            if let quantity = manualLog.quantities.first(where: { $0.id == id }) {
                return Text(quantity.name)
            } else {
                return Text("Unavailable quantity")
            }
        case .health(let metric, let sourceID):
            if let presentation = HealthMetricPresentation.supported.first(where: { $0.metric == metric }) {
                let title: LocalizedStringKey = series.isSleepDuration ? "Sleep duration" : presentation.title
                if let sourceID {
                    let source = healthMeasurements.sources(for: metric).first { $0.bundleIdentifier == sourceID }
                    return Text("\(Text(title)) (\(source?.name ?? sourceID))")
                } else {
                    return Text(title)
                }
            } else {
                return Text("Health measurement")
            }
        }
    }
}
