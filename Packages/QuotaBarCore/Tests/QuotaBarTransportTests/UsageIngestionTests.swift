import Foundation
import QuotaBarCore
import Testing
@testable import QuotaBarTransport

private let now = ISO8601DateFormatter().date(from: "2026-08-02T00:00:00Z")!
private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private struct Transcript {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "quotabar-transcripts-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func destroy() {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ lines: [String], to name: String, terminated: Bool = true) {
        let file = root.appending(path: name)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var body = lines.joined(separator: "\n")
        if terminated, !lines.isEmpty { body += "\n" }
        try? Data(body.utf8).write(to: file)
    }

    func append(_ lines: [String], to name: String, terminated: Bool = true) {
        let file = root.appending(path: name)
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        var body = lines.joined(separator: "\n")
        if terminated { body += "\n" }
        try? handle.write(contentsOf: Data(body.utf8))
    }

    static func line(
        key: String,
        output: Int,
        model: String = "claude-opus-5",
        at instant: String = "2026-07-24T15:21:21.297Z",
        version: String = "2.1.218",
        input: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0
    ) -> String {
        """
        {"message":{"id":"\(key)","model":"\(model)","usage":{"input_tokens":\(input),\
        "output_tokens":\(output),"cache_read_input_tokens":\(cacheRead),\
        "cache_creation_input_tokens":\(cacheCreation)}},"requestId":"req_\(key)",\
        "uuid":"uuid_\(key)","timestamp":"\(instant)","version":"\(version)"}
        """
    }
}

private enum IngestionSources {
    static let all = [
        "QuotaBarTransport/ClaudeCodeTranscriptScanner.swift",
        "QuotaBarTransport/TranscriptDecoder.swift",
        "QuotaBarTransport/TranscriptLine.swift",
        "QuotaBarTransport/UsageIndex.swift",
        "QuotaBarTransport/UsageIngestor.swift"
    ]

    static func read(_ relativePath: String) throws -> String {
        let sources = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources")

        return try String(contentsOf: sources.appending(path: relativePath), encoding: .utf8)
    }
}

private actor MemoryIndexStore: UsageIndexStoring {
    private var held: UsageIndex?
    private(set) var saves = 0

    func load() async -> UsageIndex? { held }

    func save(_ index: UsageIndex) async {
        held = index
        saves += 1
    }
}

private func total(_ aggregate: UsageAggregate) -> Int {
    aggregate.totalsByModel.values.reduce(.zero, +).total.value
}

@Suite("Ingestão a partir do disco")
struct UsageIngestionTests {
    @Test("o total não depende de como a leitura foi feita — inteiro, retomado e em duas execuções")
    func totalIsIndependentOfHowItWasRead() async {
        let accumulated = [100, 200, 300, 400, 500]
        let lines = accumulated.map { Transcript.line(key: "msg_same", output: $0) }

        let whole = Transcript()
        defer { whole.destroy() }
        whole.write(lines, to: "session.jsonl")
        let atOnce = await ClaudeCodeTranscriptScanner(root: whole.root)
            .scan(resuming: .empty, now: now, calendar: utc)
        #expect(total(atOnce.aggregate) == 500)
        #expect(atOnce.aggregate.report.events == 1)

        let resumed = Transcript()
        defer { resumed.destroy() }
        resumed.write(Array(lines.prefix(3)), to: "session.jsonl")
        let scanner = ClaudeCodeTranscriptScanner(root: resumed.root)
        let firstPass = await scanner.scan(resuming: .empty, now: now, calendar: utc)
        #expect(total(firstPass.aggregate) == 300)
        resumed.append(Array(lines.suffix(2)), to: "session.jsonl")
        let secondPass = await scanner.scan(resuming: firstPass.index, now: now, calendar: utc)
        #expect(total(secondPass.aggregate) == 500)
        #expect(secondPass.aggregate.report.events == 1)

        let acrossRuns = Transcript()
        defer { acrossRuns.destroy() }
        acrossRuns.write(Array(lines.prefix(3)), to: "session.jsonl")
        let store = MemoryIndexStore()
        let firstRun = UsageIngestor(
            scanner: ClaudeCodeTranscriptScanner(root: acrossRuns.root),
            store: store,
            calendar: utc
        )
        _ = await firstRun.ingest(now: now)
        acrossRuns.append(Array(lines.suffix(2)), to: "session.jsonl")
        let secondRun = UsageIngestor(
            scanner: ClaudeCodeTranscriptScanner(root: acrossRuns.root),
            store: store,
            calendar: utc
        )
        let reopened = await secondRun.ingest(now: now)
        #expect(total(reopened.aggregate) == 500)
    }

    @Test("retomar entre cada par de registros de uma chave dá sempre o mesmo total")
    func resumingAtEveryRecordBoundaryKeepsTheTotal() async {
        let accumulated = [100, 200, 300, 400, 500]
        let lines = accumulated.map { Transcript.line(key: "msg_same", output: $0) }

        for cut in 0...lines.count {
            let workspace = Transcript()
            defer { workspace.destroy() }
            let scanner = ClaudeCodeTranscriptScanner(root: workspace.root)

            workspace.write(Array(lines.prefix(cut)), to: "session.jsonl")
            let first = await scanner.scan(resuming: .empty, now: now, calendar: utc)
            if cut < lines.count {
                workspace.append(Array(lines.suffix(lines.count - cut)), to: "session.jsonl")
            }
            let second = await scanner.scan(resuming: first.index, now: now, calendar: utc)

            #expect(total(second.aggregate) == 500, "corte após \(cut) registros divergiu")
        }
    }

    @Test("pedir de novo sem mudança não decodifica nada, e o arquivo que cresceu só relê o acréscimo e o grupo da cauda")
    func requestingAgainWithoutChangeDecodesNothing() async {
        let workspace = Transcript()
        defer { workspace.destroy() }
        workspace.write((0..<30).map { Transcript.line(key: "msg_\($0)", output: 10) }, to: "session.jsonl")

        let scanner = ClaudeCodeTranscriptScanner(root: workspace.root)
        let first = await scanner.scan(resuming: .empty, now: now, calendar: utc)
        #expect(first.decodedLines == 30)

        let unchanged = await scanner.scan(resuming: first.index, now: now, calendar: utc)
        #expect(unchanged.decodedLines == 0)
        #expect(total(unchanged.aggregate) == 300)

        workspace.append((30..<40).map { Transcript.line(key: "msg_\($0)", output: 10) }, to: "session.jsonl")
        let grown = await scanner.scan(resuming: unchanged.index, now: now, calendar: utc)
        #expect(grown.decodedLines == 11, "10 acrescidos mais a única linha do grupo da cauda relido")
        #expect(grown.decodedLines < 40, "o acervo inteiro nunca é redecodificado")
        #expect(total(grown.aggregate) == 400)
    }

    @Test("a leitura não cria, altera, move nem remove arquivo algum")
    func readingLeavesTheDiskUntouched() async throws {
        let workspace = Transcript()
        defer { workspace.destroy() }
        for index in 0..<10 {
            workspace.write([Transcript.line(key: "msg_\(index)", output: 10)], to: "file\(index).jsonl")
        }

        func fingerprint() throws -> [String: Date] {
            let files = try FileManager.default.contentsOfDirectory(
                at: workspace.root,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
            return try files.reduce(into: [:]) { stamps, file in
                stamps[file.lastPathComponent] = try file.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
            }
        }

        let before = try fingerprint()
        let scanner = ClaudeCodeTranscriptScanner(root: workspace.root)
        var index = UsageIndex.empty
        for _ in 0..<3 {
            index = await scanner.scan(resuming: index, now: now, calendar: utc).index
        }

        #expect(try fingerprint() == before)
    }

    @Test("registro truncado é ignorado sem erro, e vira evento quando completado")
    func truncatedLastRecordIsIgnoredUntilComplete() async {
        let workspace = Transcript()
        defer { workspace.destroy() }
        let complete = Transcript.line(key: "msg_ok", output: 100)
        let truncated = String(Transcript.line(key: "msg_partial", output: 900).prefix(60))

        workspace.write([complete], to: "session.jsonl")
        workspace.append([truncated], to: "session.jsonl", terminated: false)

        let scanner = ClaudeCodeTranscriptScanner(root: workspace.root)
        let partial = await scanner.scan(resuming: .empty, now: now, calendar: utc)
        #expect(total(partial.aggregate) == 100)
        #expect(partial.aggregate.report.events == 1)

        workspace.append([String(Transcript.line(key: "msg_partial", output: 900).dropFirst(60))], to: "session.jsonl")
        let completed = await scanner.scan(resuming: partial.index, now: now, calendar: utc)
        #expect(total(completed.aggregate) == 1_000)
        #expect(completed.aggregate.report.events == 2)
    }

    @Test("as quatro ausências são distinguíveis entre si")
    func fourAbsencesAreDistinguishable() async {
        let missing = ClaudeCodeTranscriptScanner(
            root: FileManager.default.temporaryDirectory.appending(path: "quotabar-absent-\(UUID().uuidString)")
        )
        #expect(await missing.scan(resuming: .empty, now: now, calendar: utc).absence == .directoryMissing)

        let empty = Transcript()
        defer { empty.destroy() }
        #expect(
            await ClaudeCodeTranscriptScanner(root: empty.root)
                .scan(resuming: .empty, now: now, calendar: utc).absence == .noReadableFile
        )

        let withoutUsage = Transcript()
        defer { withoutUsage.destroy() }
        withoutUsage.write(["{\"type\":\"user\",\"uuid\":\"u1\"}"], to: "session.jsonl")
        #expect(
            await ClaudeCodeTranscriptScanner(root: withoutUsage.root)
                .scan(resuming: .empty, now: now, calendar: utc).absence == .noUsageEvent
        )

        let outsidePeriod = Transcript()
        defer { outsidePeriod.destroy() }
        outsidePeriod.write(
            [Transcript.line(key: "msg_old", output: 10, at: "2026-01-02T03:04:05.000Z")],
            to: "session.jsonl"
        )
        let present = await ClaudeCodeTranscriptScanner(root: outsidePeriod.root)
            .scan(resuming: .empty, now: now, calendar: utc)
        #expect(present.absence == nil)
        #expect(present.aggregate.series(over: .today, now: now, calendar: utc).buckets.isEmpty)
    }

    @Test("arquivo sem permissão de leitura não derruba os demais e é contado")
    func unreadableFileIsCountedWithoutBreakingTheRest() async throws {
        let workspace = Transcript()
        defer { workspace.destroy() }
        for index in 0..<9 {
            workspace.write([Transcript.line(key: "msg_\(index)", output: 10)], to: "file\(index).jsonl")
        }
        workspace.write([Transcript.line(key: "msg_locked", output: 999)], to: "locked.jsonl")
        let locked = workspace.root.appending(path: "locked.jsonl")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path())
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path()) }

        let outcome = await ClaudeCodeTranscriptScanner(root: workspace.root)
            .scan(resuming: .empty, now: now, calendar: utc)

        #expect(outcome.aggregate.report.filesRead == 9)
        #expect(outcome.aggregate.report.filesUnread == 1)
        #expect(outcome.aggregate.report.events == 9)
        #expect(outcome.aggregate.coverage.isIntact == false)
    }

    @Test("arquivo removido do disco deixa de contribuir, e o total diminui na leitura seguinte")
    func removedFileStopsContributing() async throws {
        let workspace = Transcript()
        defer { workspace.destroy() }
        workspace.write((0..<28).map { Transcript.line(key: "kept_\($0)", output: 10) }, to: "kept.jsonl")
        workspace.write((0..<12).map { Transcript.line(key: "gone_\($0)", output: 10) }, to: "gone.jsonl")

        let scanner = ClaudeCodeTranscriptScanner(root: workspace.root)
        let before = await scanner.scan(resuming: .empty, now: now, calendar: utc)
        #expect(before.aggregate.report.events == 40)
        #expect(total(before.aggregate) == 400)

        try FileManager.default.removeItem(at: workspace.root.appending(path: "gone.jsonl"))
        let after = await scanner.scan(resuming: before.index, now: now, calendar: utc)

        #expect(after.aggregate.report.events == 28)
        #expect(total(after.aggregate) == 280)
    }

    @Test("a mesma chave em dois arquivos conta uma vez, e a duplicata é registrada")
    func sameKeyAcrossFilesCountsOnce() async {
        let workspace = Transcript()
        defer { workspace.destroy() }
        workspace.write([Transcript.line(key: "msg_shared", output: 100)], to: "a-session.jsonl")
        workspace.write([Transcript.line(key: "msg_shared", output: 300)], to: "sub/b-session.jsonl")

        let outcome = await ClaudeCodeTranscriptScanner(root: workspace.root)
            .scan(resuming: .empty, now: now, calendar: utc)

        #expect(outcome.aggregate.report.events == 1)
        #expect(total(outcome.aggregate) == 300)
        #expect(outcome.aggregate.report.duplicatesDiscarded == 1)
    }

    @Test("só `.jsonl` sob o diretório de projetos é alcançado")
    func onlyJSONLinesAreReached() async {
        let workspace = Transcript()
        defer { workspace.destroy() }
        workspace.write([Transcript.line(key: "msg_ok", output: 100)], to: "session.jsonl")
        workspace.write([Transcript.line(key: "msg_hidden", output: 900)], to: "history.json")
        workspace.write([Transcript.line(key: "msg_log", output: 900)], to: "daemon.log")

        let outcome = await ClaudeCodeTranscriptScanner(root: workspace.root)
            .scan(resuming: .empty, now: now, calendar: utc)

        #expect(outcome.aggregate.report.filesRead == 1)
        #expect(total(outcome.aggregate) == 100)
    }

    @Test("sem pedido, o ator não percorre diretório nenhum")
    func nothingHappensWithoutARequest() async {
        let workspace = Transcript()
        defer { workspace.destroy() }
        workspace.write([Transcript.line(key: "msg_ok", output: 100)], to: "session.jsonl")

        let store = MemoryIndexStore()
        let ingestor = UsageIngestor(
            scanner: ClaudeCodeTranscriptScanner(root: workspace.root),
            store: store,
            calendar: utc
        )

        #expect(await ingestor.scansPerformed == 0)
        #expect(await store.saves == 0)

        _ = await ingestor.ingest(now: now)
        #expect(await ingestor.scansPerformed == 1)
    }

    @Test("o caminho da ingestão não tem como emitir requisição: nada nele alcança a rede")
    func theIngestionPathCannotReachTheNetwork() throws {
        for file in IngestionSources.all {
            let contents = try IngestionSources.read(file)

            for forbidden in ["URLSession", "URLRequest", "Network", "Socket", "http"] {
                #expect(
                    !contents.localizedCaseInsensitiveContains(forbidden),
                    "\(file) alcança a rede por `\(forbidden)`"
                )
            }
        }
    }

    @Test("a ingestão não instala temporizador nem observador de sistema de arquivos")
    func theIngestionInstallsNeitherTimerNorWatcher() throws {
        for file in IngestionSources.all {
            let contents = try IngestionSources.read(file)

            for forbidden in ["FSEvents", "DispatchSource", "NSFileCoordinator", "NSFilePresenter", "Timer("] {
                #expect(!contents.contains(forbidden), "\(file) instala `\(forbidden)`")
            }
        }
    }

    @Test("o limiar de formato mudado dispara nos dois lados e respeita a amostra mínima")
    func brokenFormatThresholdFiresOnBothSides() {
        let healthy = IngestionHealthPolicy.verdict(
            for: IngestionHealth(recentScanned: 100, recentUnrecognized: 4)
        )
        #expect(healthy == .healthy)

        let broken = IngestionHealthPolicy.verdict(
            for: IngestionHealth(
                recentScanned: 100,
                recentUnrecognized: 6,
                observedProducerVersions: ["2.1.220"]
            )
        )
        guard case .broken(let reason) = broken else {
            Issue.record("esperado quebrado, veio \(broken)")
            return
        }
        #expect(reason.observedProducerVersions == ["2.1.220"])
        #expect(reason.toleratedFraction == 0.05)

        let tooFewRecent = IngestionHealthPolicy.verdict(
            for: IngestionHealth(recentScanned: 15, recentUnrecognized: 10)
        )
        #expect(tooFewRecent == .healthy)
    }

    @Test("irreconhecível antigo não contamina a janela recente")
    func oldUnrecognizableLinesDoNotBreakTheVerdict() {
        let verdict = IngestionHealthPolicy.verdict(
            for: IngestionHealth(
                scanned: 600,
                usable: 100,
                unrecognized: 500,
                recentScanned: 100,
                recentUnrecognized: 0
            )
        )

        #expect(verdict == .healthy)
    }
}
