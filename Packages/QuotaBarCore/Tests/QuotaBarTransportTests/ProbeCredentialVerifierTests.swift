import Foundation
import QuotaBarCore
import QuotaBarCoreFixtures
import Testing

@testable import QuotaBarTransport

@Suite("Verificação da credencial por leitura real")
struct ProbeCredentialVerifierTests {
    private static let pasted = "sk-ant-oat01-valor-colado-pelo-usuario"

    private static func verifier(
        _ transport: RecordingTransport,
        version: String? = "2.1.220 (Claude Code)",
        credentials: any CredentialStoring = StubCredentials.failing(.authorizationDenied)
    ) -> ProbeCredentialVerifier {
        ProbeCredentialVerifier(
            probe: QuotaProbe(transport: transport, credentials: credentials),
            locator: ClaudeCodeLocator(environment: StubClaudeCode(version: version)),
            time: ControlledClock(at: ProviderHarness.start)
        )
    }

    private static func token() throws -> SubscriptionToken {
        try #require(SubscriptionToken(pasted: pasted))
    }

    @Test("AC-10: só há sucesso quando a leitura real devolve dado de cota")
    func aRealReadingIsWhatDeclaresSuccess() async throws {
        let transport = RecordingTransport([CannedResponse.reading()])

        let outcome = await Self.verifier(transport).verify(try Self.token())

        #expect(outcome == .success)
        #expect(transport.sentCount == 1)
    }

    @Test("AC-11: recusa e expiração são classificadas por evidência e não gravam")
    func refusalAndExpirationAreClassifiedFromEvidence() async throws {
        let refused = RecordingTransport([CannedResponse.rejected()])
        let expired = RecordingTransport([CannedResponse.rejected(ProbeResponseFixture.ErrorBody.expiredCredential)])

        let refusal = await Self.verifier(refused).verify(try Self.token())
        let expiration = await Self.verifier(expired).verify(try Self.token())

        #expect(refusal == .credentialRejected)
        #expect(expiration == .credentialExpired)
        #expect(!refusal.shouldPersist)
        #expect(!expiration.shouldPersist)
    }

    @Test("AC-12: bloqueio por política exige evidência positiva, e grava")
    func policyBlockRequiresPositiveEvidence() async throws {
        let transport = RecordingTransport([
            ProbeHTTPResponse(status: 403, headers: [:], body: ProbeResponseFixture.ErrorBody.policyRestriction)
        ])

        let outcome = await Self.verifier(transport).verify(try Self.token())

        #expect(outcome == .blockedByPolicy)
        #expect(outcome.shouldPersist)
    }

    @Test("AC-13: transporte indisponível é falha de comunicação, e grava")
    func anUnreachableOriginIsACommunicationFailure() async throws {
        let transport = RecordingTransport(failing: true)

        let outcome = await Self.verifier(transport).verify(try Self.token())

        #expect(outcome == .communicationFailure)
        #expect(outcome.shouldPersist)
    }

    @Test("AC-28: resposta sem nenhuma utilização é resposta inesperada, e não grava")
    func aResponseWithoutUtilizationsIsUnexpected() async throws {
        let transport = RecordingTransport([
            ProbeHTTPResponse(status: 200, headers: [:], body: Data(#"{"id":"msg_1"}"#.utf8))
        ])

        let outcome = await Self.verifier(transport).verify(try Self.token())

        #expect(outcome == .unexpectedResponse)
        #expect(!outcome.shouldPersist)
    }

    @Test("AC-14: sem Claude Code a verificação não acontece, e nenhuma requisição é feita")
    func withoutClaudeCodeNothingIsRequested() async throws {
        let transport = RecordingTransport([CannedResponse.reading()])

        let outcome = await Self.verifier(transport, version: nil).verify(try Self.token())

        #expect(outcome == .claudeCodeNotFound)
        #expect(transport.sentCount == 0)
    }

    @Test("REQ-7 e REQ-11: verifica-se o valor em mãos, sem passar pelo armazenamento")
    func theValueInHandIsWhatGetsVerified() async throws {
        let transport = RecordingTransport([CannedResponse.reading()])

        let outcome = await Self.verifier(transport).verify(try Self.token())

        #expect(outcome == .success)
        #expect(transport.sent.first?.headers["authorization"] == "Bearer \(Self.pasted)")
    }

    @Test("REQ-1: a versão descoberta é reaproveitada entre verificações")
    func theDiscoveredVersionIsReused() async throws {
        let environment = CountingClaudeCode()
        let transport = RecordingTransport([CannedResponse.reading()])
        let verifier = ProbeCredentialVerifier(
            probe: QuotaProbe(transport: transport, credentials: StubCredentials.configured),
            locator: ClaudeCodeLocator(environment: environment),
            time: ControlledClock(at: ProviderHarness.start)
        )

        _ = await verifier.verify(try Self.token())
        _ = await verifier.verify(try Self.token())

        #expect(environment.versionQueries == 1)
        #expect(transport.sentCount == 2)
    }
}
