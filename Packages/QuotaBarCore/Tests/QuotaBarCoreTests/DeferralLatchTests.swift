import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Condição do ciclo no instante da observação")
struct DeferralLatchTests {
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    private static func second(_ value: Int) -> Date {
        start.addingTimeInterval(TimeInterval(value))
    }

    private static func state(of planner: ProbePlanner) -> QuotaState {
        QuotaState(
            credentialPresent: true,
            snapshot: TestSnapshot.make(
                fiveHourPercent: "30",
                sevenDayPercent: nil,
                bindingWindow: .window(.fiveHour),
                readAt: start
            ),
            lastAttempt: .succeeded(at: start),
            cycle: planner.cycle,
            maxIdleCadenceSinceReading: planner.maxIdleCadenceSinceReading,
            source: .primaryProbe
        )
    }

    private static func plannerHoldingItsReading() -> ProbePlanner {
        var planner = ProbePlanner(startingAt: start)
        planner.recordReading(utilizationChanged: true, at: start)
        return planner
    }

    @Test("a condição passa a em atraso pela passagem do tempo, sem observador durante a espera")
    func timeAloneMovesTheConditionWithoutAnyObserver() {
        let published = Self.state(of: Self.plannerHoldingItsReading())

        var byPublication = DeferralLatch()
        var byLateOpening = DeferralLatch()

        #expect(published.cycle?.cadence.nature == .base, "o estado publicado guarda um veredito")
        #expect(published.cadence(at: Self.second(240), latch: &byPublication)?.nature == .base)
        #expect(published.cadence(at: Self.second(300), latch: &byPublication)?.nature == .deferredBySystem)
        #expect(published.cadence(at: Self.second(300), latch: &byLateOpening)?.nature == .deferredBySystem)
    }

    @Test("quatro minutos continuam abaixo do prazo e a condição não muda")
    func belowTheDeadlineTheConditionDoesNotMove() {
        let published = Self.state(of: Self.plannerHoldingItsReading())
        var latch = DeferralLatch()

        #expect(published.cadence(at: Self.second(240), latch: &latch)?.nature == .base)
    }

    @Test("a natureza acompanha a condição, e as quatro são distinguíveis")
    func theNatureFollowsTheConditionAndTheFourAreDistinguishable() {
        var planner = ProbePlanner(startingAt: Self.start)
        var natures: [Cadence.Nature] = []
        var latch = DeferralLatch()

        planner.recordReading(utilizationChanged: true, at: Self.start)
        natures.append(Self.state(of: planner).cadence(at: Self.second(1), latch: &latch)!.nature)

        planner.recordReading(utilizationChanged: false, at: Self.second(180))
        natures.append(Self.state(of: planner).cadence(at: Self.second(181), latch: &latch)!.nature)

        planner.recordFailure(reaction: .widenCadence, jitter: 1, at: Self.second(540))
        natures.append(Self.state(of: planner).cadence(at: Self.second(541), latch: &latch)!.nature)

        natures.append(Self.state(of: planner).cadence(at: Self.second(10_000), latch: &latch)!.nature)

        #expect(natures == [.base, .idle, .widenedByFailure, .deferredBySystem])
        #expect(Set(natures).count == 4)
    }

    @Test("três horas de atraso não escalam nem mudam qualquer outro campo do estado")
    func aVeryLongDeferralNeitherEscalatesNorChangesAnythingElse() {
        let published = Self.state(of: Self.plannerHoldingItsReading())
        var latch = DeferralLatch()

        let samples = stride(from: 300, through: 3 * 3_600, by: 600).map { elapsed in
            published.cadence(at: Self.second(elapsed), latch: &latch)!
        }

        #expect(samples.allSatisfy { $0.nature == .deferredBySystem })
        #expect(Set(samples.map(\.interval)).count == 1)
        #expect(published.maxIdleCadenceSinceReading == ProbePlanner.baseInterval)
    }

    @Test("relógio recuado não desfaz a condição")
    func aRewoundClockNeverUndoesTheCondition() {
        let published = Self.state(of: Self.plannerHoldingItsReading())
        var latch = DeferralLatch()

        #expect(published.cadence(at: Self.second(300), latch: &latch)?.nature == .deferredBySystem)
        #expect(published.cadence(at: Self.second(300 - 600), latch: &latch)?.nature == .deferredBySystem)
        #expect(published.cadence(at: Self.second(1), latch: &latch)?.nature == .deferredBySystem)
    }

    @Test("relógio adiantado antecipa a condição, e o ciclo seguinte a desfaz")
    func aFastForwardedClockAnticipatesTheConditionAndTheNextCycleUndoesIt() {
        var planner = Self.plannerHoldingItsReading()
        var latch = DeferralLatch()

        #expect(Self.state(of: planner).cadence(at: Self.second(60), latch: &latch)?.nature == .base)
        #expect(Self.state(of: planner).cadence(at: Self.second(660), latch: &latch)?.nature == .deferredBySystem)

        planner.recordReading(utilizationChanged: true, at: Self.second(660))

        #expect(Self.state(of: planner).cadence(at: Self.second(660), latch: &latch)?.nature == .base)
    }

    @Test("suspensão não observada aparece como atraso e se desfaz no ciclo seguinte")
    func anUnobservedSuspensionUndoesItselfOnTheNextCycle() {
        var planner = Self.plannerHoldingItsReading()
        var latch = DeferralLatch()
        let wake = Self.second(8 * 3_600)

        #expect(Self.state(of: planner).cadence(at: wake, latch: &latch)?.nature == .deferredBySystem)

        planner.recordReading(utilizationChanged: false, at: wake)

        #expect(Self.state(of: planner).cadence(at: wake, latch: &latch)?.nature == .idle)
    }

    @Test("a condição nunca fica presa depois de uma leitura bem-sucedida")
    func theConditionIsNeverStuck() {
        var planner = Self.plannerHoldingItsReading()
        var latch = DeferralLatch()

        for round in 1...10 {
            let late = Self.second(round * 10_000)
            #expect(Self.state(of: planner).cadence(at: late, latch: &latch)?.nature == .deferredBySystem)

            planner.recordReading(utilizationChanged: true, at: late)

            #expect(Self.state(of: planner).cadence(at: late, latch: &latch)?.nature == .base)
        }
    }

    @Test("o primeiro ciclo do primeiro uso não nasce em atraso")
    func theVeryFirstCycleIsNeverBornDeferred() {
        let planner = ProbePlanner(startingAt: Self.start)
        var latch = DeferralLatch()

        #expect(Self.state(of: planner).cadence(at: Self.start, latch: &latch)?.nature == .base)
        #expect(Self.state(of: planner).cadence(at: Self.second(1), latch: &latch)?.nature == .base)
    }

    @Test("sem ciclo agendado a condição é inexistente, e não não em atraso")
    func withoutACycleTheConditionIsAbsent() {
        var latch = DeferralLatch()

        #expect(QuotaState.unconfigured.cadence(at: Self.start, latch: &latch) == nil)
    }

    @Test("dobrado o limiar na fonte única, natureza e condição acompanham juntas")
    func theNatureAndTheConditionFollowTheInjectedThreshold() {
        var doubled = ProbePlanner(
            startingAt: Self.start,
            policy: DeferralPolicy(tolerance: DeferralPolicy.standard.tolerance * 2)
        )
        doubled.recordReading(utilizationChanged: true, at: Self.start)

        let standard = Self.plannerHoldingItsReading()

        var doubledLatch = DeferralLatch()
        var standardLatch = DeferralLatch()

        #expect(Self.state(of: doubled).cadence(at: Self.second(300), latch: &doubledLatch)?.nature == .base)
        #expect(
            Self.state(of: standard).cadence(at: Self.second(300), latch: &standardLatch)?.nature
                == .deferredBySystem
        )

        var laterDoubled = DeferralLatch()
        #expect(
            Self.state(of: doubled).cadence(at: Self.second(400), latch: &laterDoubled)?.nature
                == .deferredBySystem
        )
    }
}
