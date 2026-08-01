import Foundation
import QuotaBarCore
import QuotaBarCoreFixtures
import Testing

@testable import QuotaBarTransport

@Suite("Sonda de inferência sobre o transporte")
struct QuotaProbeTests {
    private static let readAt = Date(timeIntervalSince1970: 1_700_000_000)
    private static let version = "2.1.220"

    private static func probe(_ transport: RecordingTransport, credentials: StubCredentials = .configured) -> QuotaProbe {
        QuotaProbe(transport: transport, credentials: credentials)
    }

    private static func body(of request: ProbeRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
    }

    @Test("ADR-005: a sonda é um POST mínimo, com os cabeçalhos fixados e max_tokens 1")
    func theProbeIsTheMinimalDocumentedRequest() async throws {
        let transport = RecordingTransport([CannedResponse.reading()])

        _ = await Self.probe(transport).read(claudeCodeVersion: Self.version, at: Self.readAt)

        let request = try #require(transport.sent.first)
        #expect(request.url == URL(string: "https://api.anthropic.com/v1/messages"))
        #expect(request.headers["anthropic-version"] == "2023-06-01")
        #expect(request.headers["anthropic-beta"] == "oauth-2025-04-20")
        #expect(request.headers["content-type"] == "application/json")

        let body = Self.body(of: request)
        #expect(body["max_tokens"] as? Int == 1)
        #expect(body["model"] as? String == ProbeModel.ordered.first)
        #expect((body["messages"] as? [[String: Any]])?.count == 1)
    }

    @Test("ADR-005: o User-Agent é montado aqui, com a versão do Claude Code descoberta")
    func theUserAgentCarriesTheDiscoveredVersion() async {
        let transport = RecordingTransport([CannedResponse.reading()])

        _ = await Self.probe(transport).read(claudeCodeVersion: "9.9.9", at: Self.readAt)

        #expect(transport.sent.first?.headers["user-agent"] == "claude-code/9.9.9")
    }

    @Test("SEC REQ-14: a credencial viaja só no cabeçalho de autorização")
    func theCredentialTravelsOnlyInTheAuthorizationHeader() async throws {
        let transport = RecordingTransport([CannedResponse.reading()])

        _ = await Self.probe(transport).read(claudeCodeVersion: Self.version, at: Self.readAt)

        let request = try #require(transport.sent.first)
        let secret = StubCredentials.pasted

        #expect(request.headers["authorization"] == "Bearer \(secret)")
        #expect(!String(decoding: request.body, as: UTF8.self).contains(secret))

        for (name, value) in request.headers where name != "authorization" {
            #expect(!value.contains(secret), "\(name) carrega a credencial")
        }
    }

    @Test("Contratos §5: numa sequência em que só a terceira é leitura, o snapshot carrega a primeira candidata")
    func onlyTheReadingCommitsTheSequence() async {
        let transport = RecordingTransport([
            CannedResponse.serverError(),
            CannedResponse.throttled(),
            CannedResponse.reading()
        ])
        let probe = Self.probe(transport)

        let first = await probe.read(claudeCodeVersion: Self.version, at: Self.readAt)
        let second = await probe.read(claudeCodeVersion: Self.version, at: Self.readAt)
        let third = await probe.read(claudeCodeVersion: Self.version, at: Self.readAt)

        #expect(first == .probed(.throttled(retryAfter: nil)))
        #expect(second == .probed(.throttled(retryAfter: nil)))

        guard case .probed(.reading(let snapshot)) = third else {
            Issue.record("a terceira resposta deveria ser leitura")
            return
        }
        #expect(snapshot.readSequence == 1)
    }

    @Test("SEC REQ-15: falha de Keychain chega como falha de Keychain, não como resposta inesperada")
    func keychainFailureIsNeverRoutedThroughTheResponse() async {
        let transport = RecordingTransport([CannedResponse.reading()])

        let outcome = await Self.probe(transport, credentials: .failing(.interactionNotAllowed))
            .read(claudeCodeVersion: Self.version, at: Self.readAt)

        #expect(outcome == .credentialUnavailable(.interactionNotAllowed))
        #expect(transport.sentCount == 0)

        if case .probed = outcome {
            Issue.record("falha de Keychain não é desfecho de resposta")
        }
    }

    @Test("AC-23: falha de rede nasce no transporte como falha de comunicação")
    func networkFailureBecomesCommunicationFailure() async {
        let transport = RecordingTransport(failing: true)

        let outcome = await Self.probe(transport).read(claudeCodeVersion: Self.version, at: Self.readAt)

        #expect(outcome == .probed(.failed(.communicationFailure)))
    }

    @Test("AC-27: o corpo de sucesso não é interpretado — o dado vem só dos cabeçalhos")
    func theSuccessBodyIsDiscarded() async {
        let noise = ProbeHTTPResponse(
            status: 200,
            headers: UnifiedRateLimitHeaderFixture.complete.headers,
            body: ProbeResponseFixture.ErrorBody.withCanary("CANARIO-DE-SUCESSO")
        )
        let transport = RecordingTransport([noise])

        let outcome = await Self.probe(transport).read(claudeCodeVersion: Self.version, at: Self.readAt)

        guard case .probed(.reading(let snapshot)) = outcome else {
            Issue.record("resposta 2xx com cabeçalhos é leitura")
            return
        }
        #expect(snapshot.fiveHour.utilization == Utilization(originFraction: "0.789"))
        #expect(!String(describing: outcome).contains("CANARIO-DE-SUCESSO"))
    }

    @Test("AC-26: o corpo de erro não sobrevive à classificação")
    func theErrorBodyDoesNotSurviveClassification() async {
        let canary = "CANARIO-DE-ERRO-8F21"
        let transport = RecordingTransport([
            ProbeHTTPResponse(status: 401, headers: [:], body: ProbeResponseFixture.ErrorBody.withCanary(canary))
        ])

        let outcome = await Self.probe(transport).read(claudeCodeVersion: Self.version, at: Self.readAt)

        #expect(outcome == .probed(.failed(.credentialRejected)))
        #expect(!String(describing: outcome).contains(canary))
        #expect(!String(reflecting: outcome).contains(canary))
    }

    @Test("ADR-005: modelo indisponível recua para o próximo da lista, sem inventar erro de credencial")
    func anUnavailableModelFallsBackToTheNextOne() async {
        let transport = RecordingTransport([CannedResponse.unknownModel(), CannedResponse.reading()])

        let outcome = await Self.probe(transport).read(claudeCodeVersion: Self.version, at: Self.readAt)

        guard case .probed(.reading) = outcome else {
            Issue.record("a segunda tentativa deveria ser leitura")
            return
        }

        let models = transport.sent.compactMap { Self.body(of: $0)["model"] as? String }
        #expect(models == [ProbeModel.ordered[0], ProbeModel.ordered[1]])
    }

    @Test("AC-24: recusa com evidência de política é bloqueio; sem evidência é recusa")
    func policyEvidenceDecidesTheRefusal() async {
        let blocked = RecordingTransport([CannedResponse.rejected(ProbeResponseFixture.ErrorBody.policyRestriction)])
        let unrecognized = RecordingTransport([CannedResponse.rejected(ProbeResponseFixture.ErrorBody.notJSON)])

        let first = await Self.probe(blocked).read(claudeCodeVersion: Self.version, at: Self.readAt)
        let second = await Self.probe(unrecognized).read(claudeCodeVersion: Self.version, at: Self.readAt)

        #expect(first == .probed(.failed(.blockedByPolicy)))
        #expect(second == .probed(.failed(.credentialRejected)))
    }
}
