import Foundation
import QuotaBarCore

public struct Ingestion: Sendable {
    public let aggregate: UsageAggregate
    public let verdict: IngestionVerdict
    public let decodedLines: Int

    public init(aggregate: UsageAggregate, verdict: IngestionVerdict, decodedLines: Int) {
        self.aggregate = aggregate
        self.verdict = verdict
        self.decodedLines = decodedLines
    }
}

public actor UsageIngestor {
    private let scanner: TranscriptScanning
    private let store: UsageIndexStoring
    private let calendar: Calendar

    private var index: UsageIndex?
    public private(set) var scansPerformed = 0

    public init(
        scanner: TranscriptScanning,
        store: UsageIndexStoring,
        calendar: Calendar = .current
    ) {
        self.scanner = scanner
        self.store = store
        self.calendar = calendar
    }

    public func ingest(now: Date) async -> Ingestion {
        let resuming = await current()
        scansPerformed += 1

        let outcome = await scanner.scan(resuming: resuming, now: now, calendar: calendar)
        index = outcome.index
        await store.save(outcome.index)

        return Ingestion(
            aggregate: outcome.aggregate,
            verdict: outcome.absence.map(IngestionVerdict.absent)
                ?? IngestionHealthPolicy.verdict(for: outcome.health),
            decodedLines: outcome.decodedLines
        )
    }

    private func current() async -> UsageIndex {
        if let index { return index }

        let restored = await store.load() ?? .empty
        index = restored
        return restored
    }
}
