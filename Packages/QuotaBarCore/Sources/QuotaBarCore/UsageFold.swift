import Foundation

public enum LineRecency: Sendable, Hashable {
    case recent
    case old
}

public struct UsageFoldResult: Sendable {
    public let aggregate: UsageAggregate
    public let health: IngestionHealth
    public let ledger: UsageLedger

    public init(aggregate: UsageAggregate, health: IngestionHealth, ledger: UsageLedger) {
        self.aggregate = aggregate
        self.health = health
        self.ledger = ledger
    }
}

public struct UsageFold: Sendable {
    private let now: Date
    private let calendar: Calendar

    private var ledger: UsageLedger
    private var scanned = 0
    private var usable = 0
    private var unrecognized = 0
    private var policyRejected = 0
    private var recentScanned = 0
    private var recentUnrecognized = 0
    private var monotonicityViolations = 0
    private var producerVersions: Set<String> = []
    private var duplicatesDiscarded = 0
    private var filesRead = 0
    private var filesUnread = 0

    public init(now: Date, calendar: Calendar = .current, carrying ledger: UsageLedger = .empty) {
        self.now = now
        self.calendar = calendar
        self.ledger = ledger
    }

    public var health: IngestionHealth {
        IngestionHealth(
            scanned: scanned,
            usable: usable,
            unrecognized: unrecognized,
            recentScanned: recentScanned,
            recentUnrecognized: recentUnrecognized,
            monotonicityViolations: monotonicityViolations,
            observedProducerVersions: producerVersions
        )
    }

    public mutating func noteFileRead() { filesRead += 1 }

    public mutating func noteFileUnread() { filesUnread += 1 }

    public mutating func reindexLedger(_ ordinals: [FileIdentity: Int]) { ledger.reindex(ordinals) }

    public mutating func forgetKeys(of file: FileIdentity, fromLine line: Int) {
        ledger.dropKeys(of: file, fromLine: line)
    }

    public mutating func forgetKeysOutside(_ surviving: Set<FileIdentity>) {
        ledger.dropKeys(outside: surviving)
    }

    public mutating func absorb(
        _ record: UsageRecord,
        at position: ScanPosition,
        from file: FileIdentity = FileIdentity(digest: 0),
        recency: LineRecency = .old,
        producerVersion: String? = nil
    ) {
        note(recency: recency, producerVersion: producerVersion)

        guard record.occurredAt <= now else {
            policyRejected += 1
            return
        }

        usable += 1
        let candidate = UsageLedger.Entry(
            file: file,
            position: position,
            occurredAt: record.occurredAt,
            contributions: record.contributions
        )

        if case .duplicate(let violated) = ledger.admit(record.key, candidate) {
            duplicatesDiscarded += 1
            if violated { monotonicityViolations += 1 }
        }
    }

    public mutating func absorb(
        unusable reason: UnusableReason,
        at position: ScanPosition,
        recency: LineRecency = .old,
        producerVersion: String? = nil
    ) {
        note(recency: recency, producerVersion: producerVersion)
        unrecognized += 1
        if recency == .recent { recentUnrecognized += 1 }
    }

    public consuming func finish() -> UsageFoldResult {
        var hourly: [UsageAggregate.Address: TokenCounts] = [:]
        var earliest: Date?
        var latest: Date?
        var events = 0

        for entry in ledger.entries.values {
            events += entry.contributions.count
            earliest = min(earliest ?? entry.occurredAt, entry.occurredAt)
            latest = max(latest ?? entry.occurredAt, entry.occurredAt)

            let hourStart = BucketCalendar.start(of: entry.occurredAt, size: .hour, calendar: calendar)
            for contribution in entry.contributions {
                let address = UsageAggregate.Address(model: contribution.model, hourStart: hourStart)
                hourly[address, default: .zero] += contribution.counts
            }
        }

        let coverage = Coverage(
            earliest: earliest,
            latest: latest,
            observedBuckets: Set(hourly.keys.map(\.hourStart)).count,
            isIntact: filesUnread == 0
        )

        let report = CoverageReport(
            events: events,
            filesRead: filesRead,
            filesUnread: filesUnread,
            recordsIgnored: unrecognized + policyRejected,
            duplicatesDiscarded: duplicatesDiscarded,
            earliestEventAt: earliest,
            latestEventAt: latest
        )

        return UsageFoldResult(
            aggregate: UsageAggregate(hourly: hourly, coverage: coverage, report: report),
            health: health,
            ledger: ledger
        )
    }

    private mutating func note(recency: LineRecency, producerVersion: String?) {
        scanned += 1
        if recency == .recent { recentScanned += 1 }
        if let producerVersion, recency == .recent { producerVersions.insert(producerVersion) }
    }
}
