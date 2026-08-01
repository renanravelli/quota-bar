import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

private enum Restored {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)

    static func state(cycle: CadenceCycle? = nil, reset: Date? = nil) -> QuotaState {
        let snapshot = QuotaSnapshot(
            fiveHour: WindowReading(utilization: Utilization(originPercent: 40), resetsAt: reset, status: .allowed),
            sevenDay: WindowReading(utilization: nil, resetsAt: nil, status: .allowed),
            overallStatus: .allowed,
            nextResetAt: nil,
            bindingWindow: .window(.fiveHour),
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: 1,
            readAt: readAt,
            source: .primaryProbe
        )!

        return QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .succeeded(at: readAt),
            cycle: cycle,
            maxIdleCadenceSinceReading: .seconds(900),
            source: .primaryProbe
        )
    }

    @MainActor
    static func presenter(
        clock: @escaping @Sendable () -> Date,
        ledger: RenderLedger = RenderLedger()
    ) -> IndicatorPresenter {
        IndicatorPresenter(
            provider: RecordingQuotaStateProvider(),
            clock: clock,
            reduceMotion: { .off },
            requestRender: ledger.record
        )
    }
}

@MainActor
@Suite("Cadência de renderização do painel")
struct RenderCadenceTests {
    @Test("sobre estado restaurado, a idade tem cadência própria com o painel aberto")
    func theAgeKeepsItsOwnCadenceOverARestoredState() async throws {
        let ledger = RenderLedger()
        let presenter = Restored.presenter(
            clock: AnchoredClock(origin: Restored.readAt.addingTimeInterval(59.7)).read,
            ledger: ledger
        )
        presenter.receive(Restored.state())
        presenter.panelDidOpen()

        #expect(!presenter.countdownIsArmed, "sem reset conhecido não há contagem regressiva a correr")
        #expect(!presenter.cadenceFillIsArmed, "sem ciclo não há preenchimento a correr")
        #expect(presenter.armedAgeThreshold == Restored.readAt.addingTimeInterval(60))

        try await Task.sleep(for: .milliseconds(600))

        #expect(ledger.recorded.count == 1, "a idade pediu \(ledger.recorded.count) renderizações em vez de uma")
        #expect(presenter.armedAgeThreshold == Restored.readAt.addingTimeInterval(120), "o piso não se rearmou")
    }

    @Test("estado novo com o painel aberto rearma as cadências, sem fechar e reabrir")
    func newStateWhileThePanelIsOpenRearmsTheCadences() {
        let now = Restored.readAt.addingTimeInterval(30)
        let presenter = Restored.presenter(clock: { now })
        presenter.receive(Restored.state())
        presenter.panelDidOpen()

        #expect(!presenter.countdownIsArmed)
        #expect(!presenter.cadenceFillIsArmed)

        presenter.receive(
            Restored.state(cycle: TestCycle.scheduled(.seconds(180)), reset: now.addingTimeInterval(7_200))
        )

        #expect(presenter.cadenceFillIsArmed, "o preenchimento só voltaria a correr fechando e reabrindo o painel")
        #expect(presenter.countdownIsArmed, "a contagem só voltaria a correr fechando e reabrindo o painel")
        #expect(presenter.armedAgeThreshold == Restored.readAt.addingTimeInterval(60))
    }

    @Test("com o painel fechado nada fica armado, para as três cadências")
    func nothingIsArmedWhileThePanelIsClosed() async throws {
        let ledger = RenderLedger()
        let presenter = Restored.presenter(
            clock: AnchoredClock(origin: Restored.readAt.addingTimeInterval(59.7)).read,
            ledger: ledger
        )
        presenter.receive(
            Restored.state(
                cycle: TestCycle.scheduled(ScheduledCadence.floor),
                reset: Restored.readAt.addingTimeInterval(120)
            )
        )

        #expect(presenter.armedAgeThreshold == nil)
        #expect(!presenter.countdownIsArmed)
        #expect(!presenter.cadenceFillIsArmed)

        try await Task.sleep(for: .milliseconds(600))
        #expect(ledger.recorded.isEmpty, "a cadência de renderização cobrou atividade do repouso")
    }

    @Test("fechar o painel desarma as três cadências e nada mais é pedido")
    func closingThePanelDisarmsTheThreeCadences() async throws {
        let ledger = RenderLedger()
        let presenter = Restored.presenter(
            clock: AnchoredClock(origin: Restored.readAt.addingTimeInterval(59.7)).read,
            ledger: ledger
        )
        presenter.receive(
            Restored.state(
                cycle: TestCycle.scheduled(ScheduledCadence.floor),
                reset: Restored.readAt.addingTimeInterval(120)
            )
        )
        presenter.panelDidOpen()
        presenter.panelDidClose()
        let whileOpen = ledger.recorded.count

        #expect(presenter.armedAgeThreshold == nil)
        #expect(!presenter.countdownIsArmed)
        #expect(!presenter.cadenceFillIsArmed)

        try await Task.sleep(for: .milliseconds(600))
        #expect(ledger.recorded.count == whileOpen, "alguma cadência continuou correndo com o painel fechado")
    }

    @Test("com o reset a mais de uma hora, o piso não cria fonte de 1 Hz")
    func theFloorCreatesNoOneHertzSourceWithADistantReset() async throws {
        let ledger = RenderLedger()
        let presenter = Restored.presenter(
            clock: AnchoredClock(origin: Restored.readAt.addingTimeInterval(1)).read,
            ledger: ledger
        )
        presenter.receive(
            Restored.state(
                cycle: TestCycle.scheduled(.seconds(900)),
                reset: Restored.readAt.addingTimeInterval(7_200)
            )
        )
        presenter.panelDidOpen()

        #expect(presenter.armedAgeThreshold == Restored.readAt.addingTimeInterval(60))
        let whileOpening = ledger.recorded.count

        try await Task.sleep(for: .milliseconds(1_500))
        #expect(ledger.recorded.count == whileOpening, "o piso da idade passou a pedir renderização a cada segundo")
    }

    @Test("a linha de situação usa a régua do domínio, e não uma própria")
    func theSituationLineConsumesTheDomainRuler() {
        let presenter = Restored.presenter(clock: { Restored.readAt })
        presenter.receive(Restored.state())

        for elapsed in [0.0, 59, 60, 61, 3_599, 3_600, 7_200] as [TimeInterval] {
            let now = Restored.readAt.addingTimeInterval(elapsed)
            let age = StalenessPolicy.age(ofReadingAt: Restored.readAt, now: now)

            #expect(presenter.panelContent(at: now).situation.contains(AgeDisplay.phrase(for: age)))
        }
    }
}

@MainActor
@Suite("Relógio de renderização do painel")
struct PanelRenderClockTests {
    @Test("o instante sai do relógio no ato de construir, sem marcação prévia")
    func theInstantIsReadWhenTheContentIsBuilt() {
        let hand = SettableClock(Restored.readAt)
        let render = PanelRenderClock(clock: hand.read)
        let presenter = Restored.presenter(clock: hand.read)
        presenter.receive(Restored.state())

        hand.set(Restored.readAt.addingTimeInterval(3 * 3_600))

        let content = presenter.panelContent(at: render.instant)

        #expect(render.instant == hand.now, "o relógio devolveu um instante guardado em vez do corrente")
        #expect(content.situation.contains(AgeDisplay.phrase(for: .seconds(3 * 3_600))))
    }

    @Test("o que o temporizador produz é invalidação de quem leu o instante")
    func markingInvalidatesWhoeverReadTheInstant() {
        let render = PanelRenderClock(clock: { Restored.readAt })
        let invalidations = Invalidations()

        withObservationTracking {
            _ = render.instant
        } onChange: {
            invalidations.record()
        }

        #expect(invalidations.recorded == 0)
        render.mark()
        #expect(invalidations.recorded == 1, "marcar o relógio não invalidou quem leu o instante")
    }
}

private final class Invalidations: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var recorded: Int {
        lock.withLock { count }
    }

    func record() {
        lock.withLock { count += 1 }
    }
}
