import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Máquina de cadência e reagendamento")
struct ProbePlannerTests {
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    private static func minute(_ value: Double) -> Date {
        start.addingTimeInterval(value * 60)
    }

    private static func isDeferred(_ planner: ProbePlanner, at now: Date) -> Bool {
        now > planner.cycle.deferralDeadline
    }

    private static func plannerAfterFirstReading(utilizationChanged: Bool = false) -> ProbePlanner {
        var planner = ProbePlanner(startingAt: start)
        planner.recordReading(utilizationChanged: utilizationChanged, at: start)
        return planner
    }

    private static func idleAtCeiling() -> ProbePlanner {
        var planner = plannerAfterFirstReading()
        var instant = start

        while planner.cadence.interval < ProbePlanner.idleCeiling {
            instant = instant.addingTimeInterval(900)
            planner.recordReading(utilizationChanged: false, at: instant)
        }
        return planner
    }

    @Test("AC-13: a leitura em ritmo base publica cadência base de 3 minutos")
    func firstReadingPublishesTheBaseCadence() {
        let planner = Self.plannerAfterFirstReading(utilizationChanged: true)

        #expect(planner.cadence.nature == .base)
        #expect(planner.cadence.interval == .seconds(180))
        #expect(planner.scheduledAt == Self.minute(3))
    }

    @Test("AC-13: ociosidade cresce até o teto de 15 minutos e para nele")
    func idlenessGrowsUpToTheCeiling() {
        var planner = Self.plannerAfterFirstReading()
        #expect(planner.cadence.nature == .idle)
        #expect(planner.cadence.interval == .seconds(360))

        planner = Self.idleAtCeiling()
        #expect(planner.cadence.interval == ProbePlanner.idleCeiling)

        planner.recordReading(utilizationChanged: false, at: Self.minute(120))
        #expect(planner.cadence.interval == ProbePlanner.idleCeiling)
        #expect(planner.cadence.nature == .idle)
    }

    @Test("AC-13: as três naturezas que se agendam são distinguíveis; a quarta não se agenda")
    func theThreeScheduledNaturesAreDistinguishable() {
        var planner = Self.plannerAfterFirstReading(utilizationChanged: true)
        var natures: [ScheduledNature] = [planner.cadence.nature]

        planner.recordReading(utilizationChanged: false, at: Self.minute(3))
        natures.append(planner.cadence.nature)

        planner.recordFailure(reaction: .widenCadence, jitter: 1, at: Self.minute(9))
        natures.append(planner.cadence.nature)

        #expect(natures == [.base, .idle, .widenedByFailure])
        #expect(Set(natures) == Set(ScheduledNature.allCases))
    }

    @Test("AC-16: os três gatilhos devolvem o ritmo base")
    func theThreeTriggersRestoreTheBaseCadence() {
        var byViewer = Self.idleAtCeiling()
        byViewer.setViewerObserving(true, at: Self.minute(60))
        #expect(byViewer.cadence.nature == .base)
        #expect(byViewer.cadence.interval == ProbePlanner.baseInterval)

        var byChange = Self.idleAtCeiling()
        byChange.recordReading(utilizationChanged: true, at: Self.minute(60))
        #expect(byChange.cadence.nature == .base)
        #expect(byChange.cadence.interval == ProbePlanner.baseInterval)

        var byWake = Self.idleAtCeiling()
        byWake.resume(nextProbeAt: Self.minute(60), at: Self.minute(60))
        #expect(byWake.cadence.nature == .base)
        #expect(byWake.cadence.interval == ProbePlanner.baseInterval)
        #expect(byWake.scheduledAt == Self.minute(60))
    }

    @Test("AC-14: a maior cadência de ociosidade não decresce quando a cadência volta ao ritmo base")
    func maxIdleCadenceNeverShrinksWithoutANewReading() {
        var planner = Self.idleAtCeiling()
        #expect(planner.maxIdleCadenceSinceReading == ProbePlanner.idleCeiling)

        planner.setViewerObserving(true, at: Self.minute(60))

        #expect(planner.cadence.interval == ProbePlanner.baseInterval)
        #expect(planner.maxIdleCadenceSinceReading == ProbePlanner.idleCeiling)
    }

    @Test("AC-15: a maior cadência de ociosidade recomeça a cada leitura")
    func maxIdleCadenceRestartsOnEveryReading() {
        var planner = Self.idleAtCeiling()
        planner.setViewerObserving(true, at: Self.minute(60))

        planner.recordReading(utilizationChanged: true, at: Self.minute(61))

        #expect(planner.maxIdleCadenceSinceReading == ProbePlanner.baseInterval)
    }

    @Test("AC-14: ampliação por falha não eleva a maior cadência de ociosidade")
    func failureNeverRaisesTheIdleCeiling() {
        var planner = Self.plannerAfterFirstReading(utilizationChanged: true)

        planner.recordFailure(reaction: .widenCadence, jitter: 1, at: Self.minute(3))

        #expect(planner.cadence.interval > ProbePlanner.baseInterval)
        #expect(planner.maxIdleCadenceSinceReading == ProbePlanner.baseInterval)
    }

    @Test("AC-57: a espera por uma leitura adiada não entra na maior cadência de ociosidade")
    func deferralNeverRaisesTheIdleCeiling() {
        var planner = Self.plannerAfterFirstReading(utilizationChanged: true)

        for step in 1...10 {
            planner.setViewerObserving(true, at: Self.minute(Double(step) * 3))
            planner.setViewerObserving(false, at: Self.minute(Double(step) * 3 + 1))
        }

        #expect(planner.maxIdleCadenceSinceReading == ProbePlanner.baseInterval)
        #expect(planner.scheduledAt < Self.minute(30))
    }

    @Test("AC-17: observador entrando tarde não antecipa a leitura agendada")
    func lateViewerDoesNotAdvanceTheProbe() {
        var planner = Self.idleAtCeiling()
        let scheduled = planner.scheduledAt

        planner.setViewerObserving(true, at: scheduled.addingTimeInterval(-60))

        #expect(planner.scheduledAt == scheduled)
    }

    @Test("AC-18: observador entrando cedo acelera para o minuto 4, respeitando o piso")
    func earlyViewerAcceleratesWithinTheFloor() {
        var planner = ProbePlanner(startingAt: Self.start)
        planner.recordReading(utilizationChanged: false, at: Self.start)
        planner.recordReading(utilizationChanged: false, at: Self.start)
        planner.reschedule(at: Self.minute(15), decidedAt: Self.start)

        planner.setViewerObserving(true, at: Self.minute(1))

        #expect(planner.scheduledAt == Self.minute(4))
        #expect(planner.scheduledAt >= planner.lastProbeAt.addingTimeInterval(60))
    }

    @Test("AC-19: entrar e sair dez vezes não move o instante nem provoca leitura")
    func repeatedObservationNeverAmplifies() {
        var planner = ProbePlanner(startingAt: Self.start)
        planner.recordReading(utilizationChanged: false, at: Self.start)
        planner.reschedule(at: Self.minute(15), decidedAt: Self.start)
        planner.setViewerObserving(true, at: Self.minute(1))

        var instants: [Date] = []
        var due = 0

        for step in 0..<10 {
            let entrance = Self.minute(1 + Double(step) * 0.2)
            planner.setViewerObserving(true, at: entrance)
            instants.append(planner.scheduledAt)
            if planner.scheduledAt <= entrance { due += 1 }

            let exit = entrance.addingTimeInterval(6)
            planner.setViewerObserving(false, at: exit)
            instants.append(planner.scheduledAt)
            if planner.scheduledAt <= exit { due += 1 }
        }

        #expect(Set(instants) == [Self.minute(4)])
        #expect(due == 0)
    }

    @Test("AC-20 e AC-39: o adiamento se mede desde o agendamento vigente, não desde a leitura")
    func deferralIsMeasuredFromTheAppointmentThatIsInForce() {
        var planner = Self.idleAtCeiling()
        let reading = planner.lastProbeAt
        func minute(_ value: Double) -> Date { reading.addingTimeInterval(value * 60) }

        #expect(planner.cadence.interval == ProbePlanner.idleCeiling)
        #expect(planner.scheduledAt == minute(15))

        planner.setViewerObserving(true, at: minute(13))

        #expect(planner.scheduledAt == minute(15))
        #expect(planner.cadence.interval == ProbePlanner.baseInterval)
        #expect(Self.isDeferred(planner, at: minute(15)) == false)
        #expect(Self.isDeferred(planner, at: minute(17)) == false)
        #expect(Self.isDeferred(planner, at: minute(18)))
    }

    @Test("AC-38: a retomada reancora a medição, e o que a plataforma segurar depois dela é adiamento")
    func resumeReanchorsWithoutAmnestyingWhatComesAfter() {
        var planner = Self.idleAtCeiling()
        let wake = Self.minute(480)

        planner.resume(nextProbeAt: wake, at: wake)

        #expect(planner.cadence.interval == ProbePlanner.baseInterval)
        #expect(Self.isDeferred(planner, at: wake) == false)
        #expect(Self.isDeferred(planner, at: wake.addingTimeInterval(240)) == false)
        #expect(Self.isDeferred(planner, at: wake.addingTimeInterval(300)))
    }

    @Test("REQ-11: mudança de regime não move a última leitura nem pede leitura")
    func regimeChangeNeverCountsAsAProbe() {
        var planner = Self.plannerAfterFirstReading()
        let lastProbe = planner.lastProbeAt

        planner.setViewerObserving(true, at: Self.minute(1))
        planner.setViewerObserving(false, at: Self.minute(2))

        #expect(planner.lastProbeAt == lastProbe)
    }

    @Test("REQ-11: pedir leitura agora respeita o piso de 60 segundos desde a última")
    func immediateReadStillRespectsTheFloor() {
        var planner = Self.plannerAfterFirstReading()

        planner.requestImmediateRead(at: Self.start.addingTimeInterval(5))
        #expect(planner.scheduledAt == Self.start.addingTimeInterval(60))

        planner.requestImmediateRead(at: Self.minute(30))
        #expect(planner.scheduledAt == Self.minute(30))
    }

    @Test("AC-22: estrangulamento amplia a cadência, e Retry-After vence o cálculo local")
    func throttlingWidensAndRetryAfterWins() {
        var planner = Self.plannerAfterFirstReading(utilizationChanged: true)

        planner.recordThrottling(retryAfter: nil, jitter: 1, at: Self.minute(3))
        #expect(planner.cadence.interval == .seconds(360))
        #expect(planner.cadence.nature == .widenedByFailure)

        planner.recordThrottling(retryAfter: .seconds(1200), jitter: 0, at: Self.minute(9))
        #expect(planner.cadence.interval == .seconds(1200))
        #expect(planner.scheduledAt == Self.minute(9).addingTimeInterval(1200))
    }

    @Test("AC-34: falha tolerada na janela após o acordar não amplia a cadência")
    func toleratedFailureKeepsTheCadence() {
        var planner = Self.plannerAfterFirstReading(utilizationChanged: true)

        planner.recordFailure(reaction: .keepCadence, jitter: 1, at: Self.minute(3))

        #expect(planner.cadence.interval == ProbePlanner.baseInterval)
        #expect(planner.cadence.nature == .base)
        #expect(planner.scheduledAt == Self.minute(6))
    }

    @Test("AC-21: leitura bem-sucedida nunca amplia a cadência")
    func aReadingNeverWidensTheCadence() {
        var planner = Self.plannerAfterFirstReading(utilizationChanged: true)
        planner.recordThrottling(retryAfter: nil, jitter: 1, at: Self.minute(3))
        #expect(planner.cadence.nature == .widenedByFailure)

        planner.recordReading(utilizationChanged: true, at: Self.minute(9))

        #expect(planner.cadence.nature == .base)
        #expect(planner.cadence.interval == ProbePlanner.baseInterval)
    }
}
