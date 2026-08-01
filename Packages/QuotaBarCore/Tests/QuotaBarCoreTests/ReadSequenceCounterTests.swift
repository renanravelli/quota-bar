import Foundation
import QuotaBarCoreFixtures
import Testing

@testable import QuotaBarCore

@Suite("Identidade da leitura — a sequência só se compromete em leitura")
struct ReadSequenceCounterTests {
    private static let readAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static var readingHeaders: [String: String] {
        UnifiedRateLimitHeaderFixture.complete.headers
    }

    @Test("AC-10: leituras consecutivas de conteúdo idêntico recebem sequências distintas")
    func consecutiveReadingsGetDistinctSequences() throws {
        var counter = ReadSequenceCounter()

        let first = counter.classify(status: 200, headers: Self.readingHeaders, errorBody: nil, readAt: Self.readAt)
        let second = counter.classify(status: 200, headers: Self.readingHeaders, errorBody: nil, readAt: Self.readAt)

        guard case .reading(let one) = first, case .reading(let two) = second else {
            Issue.record("as duas respostas deveriam ser leitura")
            return
        }

        #expect(one.readSequence == 1)
        #expect(two.readSequence == 2)
        #expect(one.fiveHour.utilization == two.fiveHour.utilization)
    }

    @Test("Contratos §5: resultado que não é leitura não consome a sequência candidata")
    func onlyReadingsConsumeTheCandidate() {
        var counter = ReadSequenceCounter()

        _ = counter.classify(status: 500, headers: [:], errorBody: nil, readAt: Self.readAt)
        _ = counter.classify(status: 401, headers: [:], errorBody: ProbeResponseFixture.ErrorBody.unrecognized, readAt: Self.readAt)
        _ = counter.classify(status: 429, headers: [:], errorBody: nil, readAt: Self.readAt)
        _ = counter.classify(status: 418, headers: [:], errorBody: nil, readAt: Self.readAt)

        #expect(counter.candidate == 1)
    }

    @Test("Contratos §5: numa sequência em que só a terceira é leitura, o snapshot carrega a primeira candidata")
    func theThirdResponseCarriesTheFirstCandidate() {
        var counter = ReadSequenceCounter()

        _ = counter.classify(status: 503, headers: [:], errorBody: nil, readAt: Self.readAt)
        _ = counter.classify(status: 429, headers: [:], errorBody: nil, readAt: Self.readAt)
        let third = counter.classify(status: 200, headers: Self.readingHeaders, errorBody: nil, readAt: Self.readAt)

        guard case .reading(let snapshot) = third else {
            Issue.record("a terceira resposta deveria ser leitura")
            return
        }

        #expect(snapshot.readSequence == 1)
        #expect(counter.candidate == 2)
    }

    @Test("AC-21: cota esgotada com cabeçalhos é leitura e consome a sequência")
    func exhaustedQuotaWithHeadersIsAReading() {
        var counter = ReadSequenceCounter()

        let result = counter.classify(
            status: 429,
            headers: UnifiedRateLimitHeaderFixture.exhausted.headers,
            errorBody: nil,
            readAt: Self.readAt
        )

        guard case .reading(let snapshot) = result else {
            Issue.record("429 com cabeçalhos é leitura")
            return
        }

        #expect(snapshot.readSequence == 1)
        #expect(counter.candidate == 2)
    }
}
