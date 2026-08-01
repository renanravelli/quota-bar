import Foundation
import QuotaBarCore

public struct ScanOutcome: Sendable {
    public let aggregate: UsageAggregate
    public let health: IngestionHealth
    public let index: UsageIndex
    public let absence: UsageAbsence?
    public let decodedLines: Int

    public init(
        aggregate: UsageAggregate,
        health: IngestionHealth,
        index: UsageIndex,
        absence: UsageAbsence?,
        decodedLines: Int
    ) {
        self.aggregate = aggregate
        self.health = health
        self.index = index
        self.absence = absence
        self.decodedLines = decodedLines
    }
}

public protocol TranscriptScanning: Sendable {
    func scan(resuming index: UsageIndex, now: Date, calendar: Calendar) async -> ScanOutcome
}

public struct ClaudeCodeTranscriptScanner: TranscriptScanning {
    private static let newline: UInt8 = 0x0A
    private static let headSampleLength = 512

    public static var defaultRoot: URL {
        URL(filePath: NSHomeDirectory())
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "projects", directoryHint: .isDirectory)
    }

    private let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot
    }

    public func scan(
        resuming index: UsageIndex,
        now: Date,
        calendar: Calendar = .current
    ) async -> ScanOutcome {
        guard directoryExists else {
            return ScanOutcome(
                aggregate: .empty,
                health: IngestionHealth(),
                index: index,
                absence: .directoryMissing,
                decodedLines: 0
            )
        }

        let files = transcriptFiles()
        guard !files.isEmpty else {
            return ScanOutcome(
                aggregate: .empty,
                health: IngestionHealth(),
                index: index,
                absence: .noReadableFile,
                decodedLines: 0
            )
        }

        let identities = files.map { FileIdentity(digest: Digest.of($0.path(), salt: index.salt)) }
        let ordinals = Dictionary(
            identities.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var fold = UsageFold(now: now, calendar: calendar, carrying: index.ledger)
        fold.reindexLedger(ordinals)
        fold.forgetKeysOutside(Set(identities))

        var freshEntries: [String: UsageIndex.Entry] = [:]
        var decodedLines = 0
        var readableFiles = 0

        for (ordinal, file) in files.enumerated() {
            let identity = identities[ordinal]
            guard let attributes = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = attributes.fileSize.map(Int64.init),
                  let modifiedAt = attributes.contentModificationDate,
                  let contents = try? Data(contentsOf: file, options: .mappedIfSafe)
            else {
                fold.noteFileUnread()
                continue
            }

            readableFiles += 1
            fold.noteFileRead()

            let head = Digest.of(contents.prefix(Self.headSampleLength))
            let prior = index.entries[Self.address(of: identity)]
            let resumable = prior.map { $0.headDigest == head && size >= $0.size } ?? false

            if let prior, resumable, size == prior.size, modifiedAt == prior.modifiedAt {
                freshEntries[Self.address(of: identity)] = prior
                continue
            }

            let startOffset = resumable ? (prior?.resumeOffset ?? 0) : 0
            let startLine = resumable ? (prior?.resumeLine ?? 0) : 0

            fold.forgetKeys(of: identity, fromLine: resumable ? startLine : 0)

            let recency = now.timeIntervalSince(modifiedAt) <= Self.recentWindowSeconds ? LineRecency.recent : .old
            let region = contents[Int(min(startOffset, size))...]

            var rows: [ScannedRow] = []
            var lineOrdinal = startLine
            var cursor = region.startIndex

            while let newline = region[cursor...].firstIndex(of: Self.newline) {
                let line = region[cursor..<newline]
                let offset = Int64(cursor)
                let length = Int64(region.index(after: newline) - cursor)

                switch TranscriptDecoder.decode(line: Data(line)) {
                case .notUsageBearing:
                    rows.append(ScannedRow(key: nil, offset: offset, length: length))
                case .unusable(let reason, let producerVersion):
                    decodedLines += 1
                    fold.absorb(
                        unusable: reason,
                        at: ScanPosition(fileOrdinal: ordinal, lineOrdinal: lineOrdinal),
                        recency: recency,
                        producerVersion: producerVersion
                    )
                    rows.append(ScannedRow(key: nil, offset: offset, length: length))
                case .usable(let record, let producerVersion):
                    decodedLines += 1
                    fold.absorb(
                        record,
                        at: ScanPosition(fileOrdinal: ordinal, lineOrdinal: lineOrdinal),
                        from: identity,
                        recency: recency,
                        producerVersion: producerVersion
                    )
                    rows.append(ScannedRow(key: record.key, offset: offset, length: length))
                }

                lineOrdinal += 1
                cursor = region.index(after: newline)
            }

            let resume = ResumePolicy.resumePoint(afterFolding: rows)
            freshEntries[Self.address(of: identity)] = UsageIndex.Entry(
                size: size,
                modifiedAt: modifiedAt,
                resumeOffset: rows.isEmpty ? startOffset : resume.offset,
                resumeLine: rows.isEmpty ? startLine : Self.line(ofOffset: resume.offset, in: rows, from: startLine),
                tailKeyDigest: resume.tailKey.map { Digest.of($0.value) },
                headDigest: head
            )
        }

        let result = fold.finish()
        let absence: UsageAbsence? = if readableFiles == 0 {
            .noReadableFile
        } else if result.aggregate.report.events == 0 {
            .noUsageEvent
        } else {
            nil
        }

        return ScanOutcome(
            aggregate: result.aggregate,
            health: result.health,
            index: index.replacing(entries: freshEntries, ledger: result.ledger),
            absence: absence,
            decodedLines: decodedLines
        )
    }

    private static let recentWindowSeconds = Double(
        IngestionHealthPolicy.recentWindow.components.seconds
    )

    private static func address(of identity: FileIdentity) -> String {
        String(identity.digest)
    }

    private static func line(ofOffset offset: Int64, in rows: [ScannedRow], from firstLine: Int) -> Int {
        guard let position = rows.firstIndex(where: { $0.offset == offset }) else { return firstLine }
        return firstLine + position
    }

    private var directoryExists: Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: root.path(), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private func transcriptFiles() -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return walker
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.path() < $1.path() }
    }
}
