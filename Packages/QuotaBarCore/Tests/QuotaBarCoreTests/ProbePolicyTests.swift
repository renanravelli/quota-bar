import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Backoff, piso e política de rede")
struct ProbePolicyTests {
    @Test("o piso de 60 segundos recusa qualquer cadência menor")
    func floorRejectsAnythingBelowSixtySeconds() {
        #expect(Cadence.floor == .seconds(60))
        #expect(Cadence(interval: .seconds(59), nature: .base) == nil)
        #expect(Cadence(interval: .seconds(60), nature: .base)?.interval == .seconds(60))
    }

    @Test("a falha de comunicação amplia a cadência, dobrando com jitter")
    func communicationFailureWidensTheCadence() {
        let current = Duration.seconds(180)

        #expect(BackoffPolicy.widened(from: current, retryAfter: nil, jitter: 0) == current)
        #expect(BackoffPolicy.widened(from: current, retryAfter: nil, jitter: 1) == .seconds(360))
        #expect(BackoffPolicy.widened(from: current, retryAfter: nil, jitter: 0.5) == .seconds(270))
    }

    @Test("o jitter nunca encurta a cadência nem passa do dobro")
    func jitterStaysBetweenTheCurrentCadenceAndItsDouble() {
        let current = Duration.seconds(180)

        for step in 0...10 {
            let widened = BackoffPolicy.widened(from: current, retryAfter: nil, jitter: Double(step) / 10)
            #expect(widened >= current)
            #expect(widened <= current * 2)
        }
    }

    @Test("a ampliação sucessiva para no teto de 30 minutos")
    func wideningStopsAtTheCeiling() {
        var interval = Duration.seconds(180)

        for _ in 0..<20 {
            interval = BackoffPolicy.widened(from: interval, retryAfter: nil, jitter: 1)
        }

        #expect(BackoffPolicy.ceiling == .seconds(1800))
        #expect(interval == BackoffPolicy.ceiling)
    }

    @Test("Retry-After vence o cálculo local, respeitado o piso")
    func retryAfterBeatsTheLocalCalculation() {
        let current = Duration.seconds(180)

        #expect(BackoffPolicy.widened(from: current, retryAfter: .seconds(600), jitter: 1) == .seconds(600))
        #expect(BackoffPolicy.widened(from: current, retryAfter: .seconds(10), jitter: 1) == Cadence.floor)
        #expect(BackoffPolicy.widened(from: current, retryAfter: .seconds(3600), jitter: 0) == .seconds(3600))
    }

    @Test("falha de comunicação manda espaçar as leituras")
    func communicationFailureAsksForWidening() {
        #expect(NetworkPolicy.reaction(to: .communicationFailure, withinWakeTolerance: false) == .widenCadence)
    }

    @Test("a política mantém a cadência quando a rede falha dentro da tolerância do acordar")
    func networkUnavailableRightAfterWakeIsTolerated() {
        #expect(NetworkPolicy.reaction(to: .communicationFailure, withinWakeTolerance: true) == .keepCadence)
    }

    @Test("recusa de credencial interrompe as leituras periódicas")
    func credentialRefusalStopsPeriodicProbing() {
        let halting: [FailureReason] = [
            .credentialRejected,
            .credentialExpired,
            .credentialUnreadable,
            .blockedByPolicy
        ]

        for reason in halting {
            #expect(NetworkPolicy.reaction(to: reason, withinWakeTolerance: false) == .stopProbing)
            #expect(NetworkPolicy.reaction(to: reason, withinWakeTolerance: true) == .stopProbing)
        }
    }

    @Test("sem Claude Code não há leitura alguma, com ou sem tolerância de acordar")
    func claudeCodeNotFoundStopsProbing() {
        #expect(NetworkPolicy.reaction(to: .claudeCodeNotFound, withinWakeTolerance: false) == .stopProbing)
        #expect(NetworkPolicy.reaction(to: .claudeCodeNotFound, withinWakeTolerance: true) == .stopProbing)
    }

    @Test("os sete motivos têm reação definida, sem caso omisso")
    func everyFailureReasonHasAReaction() {
        #expect(FailureReason.allCases.count == 7)

        let reactions = FailureReason.allCases.map {
            NetworkPolicy.reaction(to: $0, withinWakeTolerance: false)
        }

        #expect(reactions.count == FailureReason.allCases.count)
        #expect(Set(reactions) == [.stopProbing, .widenCadence, .keepCadence])
    }

    @Test("resposta inesperada não entra em ciclo de espaçamento")
    func unexpectedResponseDoesNotWiden() {
        #expect(NetworkPolicy.reaction(to: .unexpectedResponse, withinWakeTolerance: false) == .keepCadence)
    }
}
