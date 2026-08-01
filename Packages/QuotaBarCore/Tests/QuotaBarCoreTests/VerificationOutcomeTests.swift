import Foundation
import Testing

@testable import QuotaBarCore

@Suite("QB-SEC-001 — desfecho da verificação e tabela de gravação")
struct VerificationOutcomeTests {
    private static let persisting: Set<VerificationOutcome> = [
        .success,
        .blockedByPolicy,
        .communicationFailure
    ]

    private static let notPersisting: Set<VerificationOutcome> = [
        .credentialRejected,
        .credentialExpired,
        .unexpectedResponse,
        .claudeCodeNotFound
    ]

    @Test("AC-29: os sete desfechos de REQ-8 existem, e nenhum outro")
    func theSevenOutcomesAreExactlyTheSpecifiedOnes() {
        #expect(Set(VerificationOutcome.allCases) == Self.persisting.union(Self.notPersisting))
        #expect(VerificationOutcome.allCases.count == 7)
    }

    @Test("AC-29: cada desfecho decide gravar ou não, sem caso omisso")
    func everyOutcomeDecidesPersistence() {
        let decided = VerificationOutcome.allCases.filter(\.shouldPersist)

        #expect(Set(decided) == Self.persisting)
        #expect(Set(VerificationOutcome.allCases.filter { !$0.shouldPersist }) == Self.notPersisting)
    }

    @Test("AC-10: sucesso grava, porque há evidência de que funciona")
    func successPersists() {
        #expect(VerificationOutcome.success.shouldPersist)
    }

    @Test("AC-11: credencial recusada e credencial expirada não gravam")
    func rejectedAndExpiredDoNotPersist() {
        #expect(!VerificationOutcome.credentialRejected.shouldPersist)
        #expect(!VerificationOutcome.credentialExpired.shouldPersist)
    }

    @Test("AC-12: uso bloqueado por política grava, porque a credencial está boa")
    func policyBlockPersists() {
        #expect(VerificationOutcome.blockedByPolicy.shouldPersist)
    }

    @Test("AC-13: falha de comunicação grava, porque o problema é a rede")
    func communicationFailurePersists() {
        #expect(VerificationOutcome.communicationFailure.shouldPersist)
    }

    @Test("AC-28: resposta inesperada não grava, porque não há evidência de coisa alguma")
    func unexpectedResponseDoesNotPersist() {
        #expect(!VerificationOutcome.unexpectedResponse.shouldPersist)
    }

    @Test("AC-14: verificação impossível por falta de Claude Code não grava")
    func claudeCodeNotFoundDoesNotPersist() {
        #expect(!VerificationOutcome.claudeCodeNotFound.shouldPersist)
    }

    @Test("AC-29: a classificação da resposta decide o desfecho da verificação")
    func probeResultDecidesTheOutcome() {
        let snapshot = TestSnapshot.make(
            fiveHourPercent: "42",
            sevenDayPercent: "67",
            bindingWindow: .window(.fiveHour)
        )

        #expect(VerificationOutcome(probeResult: .reading(snapshot)) == .success)
        #expect(VerificationOutcome(probeResult: .throttled(retryAfter: nil)) == .communicationFailure)
        #expect(VerificationOutcome(probeResult: .throttled(retryAfter: .seconds(30))) == .communicationFailure)
        #expect(VerificationOutcome(probeResult: .failed(.credentialRejected)) == .credentialRejected)
        #expect(VerificationOutcome(probeResult: .failed(.credentialExpired)) == .credentialExpired)
        #expect(VerificationOutcome(probeResult: .failed(.blockedByPolicy)) == .blockedByPolicy)
        #expect(VerificationOutcome(probeResult: .failed(.communicationFailure)) == .communicationFailure)
        #expect(VerificationOutcome(probeResult: .failed(.unexpectedResponse)) == .unexpectedResponse)
        #expect(VerificationOutcome(probeResult: .failed(.claudeCodeNotFound)) == .claudeCodeNotFound)
    }

    @Test("AC-29: credencial ilegível não é desfecho desta verificação, e o que não tem evidência não grava")
    func unreadableCredentialIsNotAnOutcomeOfThisVerification() {
        let outcome = VerificationOutcome(probeResult: .failed(.credentialUnreadable))

        #expect(outcome == .unexpectedResponse)
        #expect(!outcome.shouldPersist)
    }
}
