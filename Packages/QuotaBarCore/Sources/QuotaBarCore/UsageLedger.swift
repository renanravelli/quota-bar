import Foundation

public struct FileIdentity: Sendable, Hashable, Codable {
    public let digest: UInt64

    public init(digest: UInt64) {
        self.digest = digest
    }
}

public enum LedgerOutcome: Sendable, Hashable {
    case accepted
    case duplicate(monotonicityViolated: Bool)
}

public struct UsageLedger: Sendable, Hashable {
    public struct Entry: Sendable, Hashable {
        public let file: FileIdentity
        public let position: ScanPosition
        public let occurredAt: Date
        public let contributions: [ModelContribution]

        public init(
            file: FileIdentity,
            position: ScanPosition,
            occurredAt: Date,
            contributions: [ModelContribution]
        ) {
            self.file = file
            self.position = position
            self.occurredAt = occurredAt
            self.contributions = contributions
        }

        public var total: Int {
            contributions.reduce(0) { $0 + $1.counts.total.value }
        }

        func relocated(toFileOrdinal ordinal: Int) -> Entry {
            Entry(
                file: file,
                position: ScanPosition(fileOrdinal: ordinal, lineOrdinal: position.lineOrdinal),
                occurredAt: occurredAt,
                contributions: contributions
            )
        }
    }

    public static let empty = UsageLedger(entries: [:])

    public private(set) var entries: [UsageKey: Entry]

    public init(entries: [UsageKey: Entry]) {
        self.entries = entries
    }

    public var count: Int { entries.count }

    public var eventCount: Int {
        entries.values.reduce(0) { $0 + $1.contributions.count }
    }

    @discardableResult
    public mutating func admit(_ key: UsageKey, _ candidate: Entry) -> LedgerOutcome {
        guard let held = entries[key] else {
            entries[key] = candidate
            return .accepted
        }

        let supersedes = candidate.position >= held.position
        if supersedes { entries[key] = candidate }

        let laterIsSmaller = supersedes && candidate.total < held.total
        let earlierIsLarger = !supersedes && candidate.total > held.total
        return .duplicate(monotonicityViolated: laterIsSmaller || earlierIsLarger)
    }

    public mutating func reindex(_ ordinals: [FileIdentity: Int]) {
        entries = entries.compactMapValues { entry in
            ordinals[entry.file].map(entry.relocated(toFileOrdinal:))
        }
    }

    public mutating func dropKeys(outside surviving: Set<FileIdentity>) {
        entries = entries.filter { surviving.contains($0.value.file) }
    }

    public mutating func dropKeys(of file: FileIdentity, fromLine line: Int) {
        entries = entries.filter { $0.value.file != file || $0.value.position.lineOrdinal < line }
    }
}
