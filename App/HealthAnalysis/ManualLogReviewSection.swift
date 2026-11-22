import HealthAnalysisCore
import SwiftUI

struct ManualLogReviewSection: View {
    let log: ManualLog
    let day: ManualLogDay
    @State private var failedReviewDay: ManualLogDay?

    var body: some View {
        let review = log.review(on: day)
        Section("Day review") {
            if let review {
                Text(review.isCurrent ? LocalizedStringKey("Day reviewed") : "Review needed")
                LabeledContent("Last reviewed") {
                    Text(review.reviewedAt, format: .dateTime.year().month().day().hour().minute())
                }
            } else {
                Text("Day not reviewed")
            }

            Button("Confirm day") {
                do {
                    try log.confirmDay(day)
                    failedReviewDay = nil
                } catch {
                    failedReviewDay = day
                }
            }
            .disabled(!log.canConfirmDay(day) || review?.isCurrent == true)

            if failedReviewDay == day {
                Text("Couldn’t confirm this day. Try again.")
                    .foregroundStyle(.red)
            }
        }
    }
}
