import HealthAnalysisCore
import SwiftUI

struct FirstUseView: View {
    let application: HealthAnalysisApplication
    let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var finishFailed = false

    private var setup: FirstUseSetup { application.firstUse }
    private var history: HealthMeasurementHistory { application.healthMeasurements }

    var body: some View {
        Form {
            switch setup.step {
            case .healthAccess: explanation
            case .coverage: coverage
            case .manualTracking: manualTracking
            case .complete: EmptyView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if setup.step == .coverage {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review manual tracking", action: setup.continueToTracking)
                        .disabled(history.readState == .loading)
                }
            }
        }
    }

    private var title: LocalizedStringKey {
        switch setup.step {
        case .healthAccess, .complete: "Get started"
        case .coverage: "Health coverage"
        case .manualTracking: "Manual tracking"
        }
    }

    private var explanation: some View {
        Section("Apple Health") {
            Text("Health Analysis reads Apple Health to show your measurements and explore how they relate to your tracked behaviors. It keeps your data on this device.")
            Text("Access is read-only. Health Analysis doesn’t write to Apple Health.")
            Button("Request read access") {
                Task { await setup.requestHealthAccess() }
            }
            Button("Continue without checking", action: setup.continueWithoutHealthAccess)
        }
    }

    @ViewBuilder
    private var coverage: some View {
        Section {
            HealthReadStatus(history: history, showsInitialState: false, showsEmptyHistory: false)
            switch history.readState {
            case .idle, .failed:
                Button("Request read access") {
                    Task { await setup.requestHealthAccess() }
                }
            case .loading, .loaded:
                EmptyView()
            }
        }
        if history.readState != .loading || history.hasReadableRecords {
            FirstUseCoverageSections(history: history)
        }
    }

    @ViewBuilder
    private var manualTracking: some View {
        Section {
            Text("Add any variables you want to log. You can skip this step and add them later in Settings.")
            Button("Continue to Explore", action: finish)
            if finishFailed {
                Text("Couldn’t save setup progress. Try again.")
                    .foregroundStyle(.secondary)
            }
            if !application.manualLog.isStoreAvailable {
                Text("Couldn’t open the daily log")
            }
        }
        SuggestedTrackingSection(log: application.manualLog)
    }

    private func finish() {
        do {
            try setup.finish()
            dismiss()
            onFinish()
        } catch {
            finishFailed = true
        }
    }
}
