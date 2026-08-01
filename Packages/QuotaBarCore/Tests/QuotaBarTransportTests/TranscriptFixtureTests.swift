import Foundation
import QuotaBarCore
import QuotaBarCoreFixtures
import Testing
@testable import QuotaBarTransport

private func decode(_ line: String) -> DecodedLine {
    TranscriptDecoder.decode(line: Data(line.utf8))
}

private func record(_ line: String) -> UsageRecord? {
    guard case .usable(let record, _) = decode(line) else { return nil }
    return record
}

@Suite("Fixtures transcritas do corpo real")
struct TranscriptFixtureTests {
    @Test("o fallback de dois modelos vira dois eventos, cada um com a sua parcela")
    func twoModelFallbackDecomposes() throws {
        let decoded = try #require(record(TranscriptFixtures.twoModelFallback))

        #expect(decoded.contributions.count == 2)
        let byModel = Dictionary(
            uniqueKeysWithValues: decoded.contributions.map { ($0.model, $0.counts.total.value) }
        )
        #expect(byModel[.model("claude-fable-5")] == 29_655)
        #expect(byModel[.model("claude-opus-4-8")] == 12_000)
        #expect(decoded.counts.total.value == 41_655)
    }

    @Test("a iteração única sem modelo herda o modelo do registro")
    func singleIterationInheritsModel() throws {
        let decoded = try #require(record(TranscriptFixtures.singleIterationWithoutModel))

        #expect(decoded.contributions.map(\.model) == [.model("claude-opus-5")])
        #expect(decoded.counts.total.value == 1_052)
    }

    @Test("o registro sintético entra com identidade própria, e não é descartado")
    func syntheticKeepsItsOwnCategory() throws {
        let decoded = try #require(record(TranscriptFixtures.syntheticModel))

        #expect(decoded.contributions.map(\.model) == [.nonModel("<synthetic>")])
        #expect(decoded.counts.total.value == 0)
    }

    @Test("a linha sem identificador de requisição usa a identidade de mensagem")
    func lineWithoutRequestIdentifierStillHasIdentity() throws {
        let decoded = try #require(record(TranscriptFixtures.withoutRequestIdentifier))

        #expect(decoded.key.origin == .messageID)
        #expect(decoded.key.value == "msg_01WithoutRequestIdentifier")
    }

    @Test("sem nenhuma das três identidades o registro é irreconhecível")
    func lineWithoutAnyIdentifierIsUnusable() {
        guard case .unusable(let reason, _) = decode(TranscriptFixtures.withoutAnyIdentifier) else {
            Issue.record("esperado irreconhecível")
            return
        }

        #expect(reason == .missingKey)
    }

    @Test("a identidade acumulada em várias linhas conta uma vez, com a última")
    func accumulatingIdentityCountsOnce() {
        var fold = UsageFold(now: Date(timeIntervalSince1970: 2_000_000_000), calendar: .current)
        fold.noteFileRead()

        for (index, line) in TranscriptFixtures.accumulatingIdentity.enumerated() {
            guard case .usable(let decoded, _) = decode(line) else {
                Issue.record("linha \(index) não decodificou")
                return
            }
            fold.absorb(decoded, at: ScanPosition(fileOrdinal: 0, lineOrdinal: index))
        }

        let aggregate = fold.finish().aggregate
        #expect(aggregate.report.events == 1)
        #expect(aggregate.totalsByModel.values.reduce(.zero, +).output == 210)
    }

    @Test("a cauda truncada não decodifica e não vira evento")
    func truncatedTailIsUnusable() {
        guard case .unusable(let reason, _) = decode(TranscriptFixtures.truncatedTail) else {
            Issue.record("esperado irreconhecível")
            return
        }

        #expect(reason == .undecodableLine)
    }

    @Test("a versão do produtor é observada nas linhas recentes")
    func producerVersionIsObserved() {
        var fold = UsageFold(now: Date(timeIntervalSince1970: 2_000_000_000), calendar: .current)
        guard case .usable(let decoded, let version) = decode(TranscriptFixtures.singleIterationWithoutModel) else {
            Issue.record("não decodificou")
            return
        }

        fold.absorb(
            decoded,
            at: ScanPosition(fileOrdinal: 0, lineOrdinal: 0),
            recency: .recent,
            producerVersion: version
        )

        #expect(fold.health.observedProducerVersions == ["2.1.220"])
    }
}
