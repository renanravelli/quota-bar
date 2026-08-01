import Foundation
import QuotaBarCore

enum Digest {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x1000_0000_01b3

    static func of(_ bytes: some Sequence<UInt8>, salt: UInt64 = 0) -> UInt64 {
        var hash = offsetBasis ^ salt
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    static func of(_ text: String, salt: UInt64 = 0) -> UInt64 {
        of(Array(text.utf8), salt: salt)
    }
}

public struct UsageIndex: Sendable, Codable, Hashable {
    public struct Entry: Sendable, Codable, Hashable {
        public let size: Int64
        public let modifiedAt: Date
        public let resumeOffset: Int64
        public let resumeLine: Int
        public let tailKeyDigest: UInt64?
        public let headDigest: UInt64
    }

    struct StoredContribution: Sendable, Codable, Hashable {
        let identifier: String
        let namesAModel: Bool
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheCreation: Int
    }

    struct StoredEntry: Sendable, Codable, Hashable {
        let keyValue: String
        let keyOrigin: Int
        let fileDigest: UInt64
        let fileOrdinal: Int
        let lineOrdinal: Int
        let occurredAt: Date
        let contributions: [StoredContribution]
    }

    public static let currentVersion = 1

    public let version: Int
    public let salt: UInt64
    public let entries: [String: Entry]
    let ledgerEntries: [StoredEntry]

    public static let empty = UsageIndex(
        version: currentVersion,
        salt: UInt64.random(in: UInt64.min...UInt64.max),
        entries: [:],
        ledgerEntries: []
    )

    init(version: Int, salt: UInt64, entries: [String: Entry], ledgerEntries: [StoredEntry]) {
        self.version = version
        self.salt = salt
        self.entries = entries
        self.ledgerEntries = ledgerEntries
    }

    var ledger: UsageLedger {
        UsageLedger(
            entries: Dictionary(
                uniqueKeysWithValues: ledgerEntries.compactMap { stored in
                    guard let origin = UsageKey.Origin.decoded(stored.keyOrigin) else { return nil }
                    return (
                        UsageKey(value: stored.keyValue, origin: origin),
                        UsageLedger.Entry(
                            file: FileIdentity(digest: stored.fileDigest),
                            position: ScanPosition(
                                fileOrdinal: stored.fileOrdinal,
                                lineOrdinal: stored.lineOrdinal
                            ),
                            occurredAt: stored.occurredAt,
                            contributions: stored.contributions.map {
                                ModelContribution(
                                    model: $0.namesAModel ? .model($0.identifier) : .nonModel($0.identifier),
                                    counts: TokenCounts(
                                        input: $0.input,
                                        output: $0.output,
                                        cacheRead: $0.cacheRead,
                                        cacheCreation: $0.cacheCreation
                                    )
                                )
                            }
                        )
                    )
                }
            )
        )
    }

    func replacing(entries: [String: Entry], ledger: UsageLedger) -> UsageIndex {
        UsageIndex(
            version: Self.currentVersion,
            salt: salt,
            entries: entries,
            ledgerEntries: ledger.entries.map { key, entry in
                StoredEntry(
                    keyValue: key.value,
                    keyOrigin: key.origin.encoded,
                    fileDigest: entry.file.digest,
                    fileOrdinal: entry.position.fileOrdinal,
                    lineOrdinal: entry.position.lineOrdinal,
                    occurredAt: entry.occurredAt,
                    contributions: entry.contributions.map {
                        StoredContribution(
                            identifier: $0.model.recordedIdentifier,
                            namesAModel: $0.model.namesAModel,
                            input: $0.counts.input,
                            output: $0.counts.output,
                            cacheRead: $0.counts.cacheRead,
                            cacheCreation: $0.counts.cacheCreation
                        )
                    }
                )
            }
        )
    }
}

private extension UsageKey.Origin {
    var encoded: Int {
        switch self {
        case .messageID: 0
        case .requestID: 1
        case .uuid: 2
        }
    }

    static func decoded(_ raw: Int) -> Self? {
        switch raw {
        case 0: .messageID
        case 1: .requestID
        case 2: .uuid
        default: nil
        }
    }
}

public protocol UsageIndexStoring: Sendable {
    func load() async -> UsageIndex?
    func save(_ index: UsageIndex) async
}

public struct FileUsageIndexStore: UsageIndexStoring {
    public static let applicationSupport = FileUsageIndexStore(fileURL: applicationSupportFileURL)

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() async -> UsageIndex? {
        guard let data = try? Data(contentsOf: fileURL),
              let index = try? JSONDecoder().decode(UsageIndex.self, from: data),
              index.version == UsageIndex.currentVersion
        else { return nil }

        return index
    }

    public func save(_ index: UsageIndex) async {
        guard let data = try? JSONEncoder().encode(index) else { return }

        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private static var applicationSupportFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")

        return base
            .appending(path: "QuotaBar", directoryHint: .isDirectory)
            .appending(path: "usage-index.json", directoryHint: .notDirectory)
    }
}
