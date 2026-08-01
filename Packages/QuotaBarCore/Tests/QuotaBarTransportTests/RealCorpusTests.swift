import Foundation
import QuotaBarCore
import Testing
@testable import QuotaBarTransport

private let realCorpusEnabled = ProcessInfo.processInfo.environment["QUOTABAR_REAL_CORPUS"] != nil

@Suite("O corpo real desta máquina", .enabled(if: realCorpusEnabled))
struct RealCorpusTests {
    @Test("a ingestão reproduz o total canônico deduplicado, e os fatores de inflação")
    func deduplicatedTotalMatchesTheCanonicalMeasurement() async throws {
        let scanner = ClaudeCodeTranscriptScanner()
        let started = Date()
        let outcome = await scanner.scan(resuming: .empty, now: Date(), calendar: .current)
        let elapsed = Date().timeIntervalSince(started)

        let deduplicated = outcome.aggregate.totalsByModel.values
            .reduce(TokenCounts.zero, +)
            .total.value

        let byModel = outcome.aggregate.totalsByModel
            .sorted { $0.value.total.value > $1.value.total.value }
            .map { "\($0.key.recordedIdentifier)=\($0.value.total.value)" }

        print("""

        ===== corpo real =====
        arquivos lidos ......... \(outcome.aggregate.report.filesRead)
        arquivos não lidos ..... \(outcome.aggregate.report.filesUnread)
        linhas decodificadas ... \(outcome.decodedLines)
        eventos ................ \(outcome.aggregate.report.events)
        duplicatas descartadas . \(outcome.aggregate.report.duplicatesDiscarded)
        registros ignorados .... \(outcome.aggregate.report.recordsIgnored)
        modelos distintos ...... \(outcome.aggregate.models.count)
        total deduplicado ...... \(deduplicated)
        violações monotonia .... \(outcome.health.monotonicityViolations)
        versões do produtor .... \(outcome.health.observedProducerVersions.sorted())
        varredura completa ..... \(String(format: "%.3f", elapsed)) s
        por modelo ............. \(byModel.joined(separator: " "))
        ======================

        """)

        #expect(deduplicated > 0)
        #expect(outcome.health.monotonicityViolations == 0)
        #expect(outcome.aggregate.report.filesUnread == 0)
    }

    @Test("uma segunda leitura, sem mudança, não decodifica registro algum")
    func secondReadDecodesNothing() async {
        let scanner = ClaudeCodeTranscriptScanner()
        let first = await scanner.scan(resuming: .empty, now: Date(), calendar: .current)

        let started = Date()
        let second = await scanner.scan(resuming: first.index, now: Date(), calendar: .current)
        let elapsed = Date().timeIntervalSince(started)

        print("""

        leitura incremental .... \(String(format: "%.3f", elapsed)) s
        linhas decodificadas ... \(second.decodedLines)

        """)

        #expect(second.decodedLines <= first.decodedLines / 100)
    }
}
