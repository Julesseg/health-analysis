import Foundation
import Observation

@MainActor
@Observable
public final class HealthMeasurementHistory {
    public enum ReadState: Equatable, Sendable {
        case idle
        case loading
        case loaded(readableCount: Int)
        case failed(HealthMeasurementReadFailure)
    }

    public private(set) var readState: ReadState = .idle
    public private(set) var history: [HealthMeasurement] = []
    public private(set) var lastSuccessfulReadAt: Date?
    public var latest: HealthMeasurement? { history.first }

    private let source: (any HealthMeasurementSource)?

    nonisolated init(source: (any HealthMeasurementSource)?) {
        self.source = source
    }

    public func requestAccessAndRefresh() async {
        await load(requestingAccess: true)
    }

    public func refresh() async {
        await load(requestingAccess: false)
    }

    private func load(requestingAccess: Bool) async {
        guard readState != .loading else { return }
        guard let source else {
            readState = .failed(.unavailable)
            return
        }

        let previousState = readState
        readState = .loading
        var failure: HealthMeasurementReadFailure = .request
        do {
            if requestingAccess {
                try await source.requestReadAccess()
            }
            failure = .read
            let records = try await source.readMeasurements()
            try Task.checkCancellation()
            let readableIDs = Set(records.map(\.id))
            var imported = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
            for record in records {
                imported[record.id] = record
            }
            history = imported.values.sorted {
                let left = ($0.startDate, $0.endDate)
                let right = ($1.startDate, $1.endDate)
                return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
            }
            lastSuccessfulReadAt = .now
            readState = .loaded(readableCount: readableIDs.count)
        } catch is CancellationError {
            readState = previousState
        } catch {
            readState = .failed(error as? HealthMeasurementReadFailure ?? failure)
        }
    }
}
