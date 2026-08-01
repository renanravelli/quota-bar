import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

@MainActor
@Suite("Declaração de adiamento no painel")
struct DeferralDeclarationTests {
    private static let deferredLine =
        "Atualização adiada pelo sistema — o intervalo pretendido é a cada 3 minutos."
    private static let baseLine = "Atualizando a cada 3 minutos — ritmo base."

    @Test("QB-APP-001 AC-52: cinco minutos depois do agendamento, a linha declara o atraso em curso")
    func theCadenceLineDeclaresTheDelayInProgress() {
        let presenter = Journey.openPanel(over: Journey.state())
        let content = presenter.panelContent(at: Journey.readAt.addingTimeInterval(300))

        #expect(content.cadenceLine == Self.deferredLine)
        #expect(content.cadenceLine?.contains("ritmo base") == false)
    }

    @Test("QB-APP-001 AC-52: o painel usa o prazo fornecido e não recalcula o limiar")
    func thePanelDoesNotRecomputeTheThreshold() {
        let observed = Journey.readAt.addingTimeInterval(300)
        let published = Journey.openPanel(over: Journey.state()).panelContent(at: observed)
        let laterDeadline = Journey.openPanel(
            over: Journey.state(deferralDeadline: Journey.readAt.addingTimeInterval(600))
        ).panelContent(at: observed)

        #expect(published.cadenceLine == Self.deferredLine)
        #expect(
            laterDeadline.cadenceLine == Self.baseLine,
            "o painel refez a conta do limiar em vez de usar o prazo publicado"
        )
    }

    @Test("QB-APP-001 AC-54: depois de acordar, a linha declara ritmo base e o período aparece como idade")
    func wakingUpDoesNotDeclareDeferral() {
        let resumedAt = Journey.readAt.addingTimeInterval(8 * 3_600)
        let state = Journey.state(deferralDeadline: resumedAt.addingTimeInterval(270))
        let presenter = Journey.openPanel(over: state, clock: { resumedAt })
        let content = presenter.panelContent(at: resumedAt)

        #expect(content.cadenceLine == Self.baseLine)
        #expect(content.cadenceLine?.contains("adiada") == false)
        #expect(Journey.isMarkedStale(content.situation))
        #expect(content.situation.contains("há 8 horas"))
        #expect(presenter.indicatorText == "5h ~30%")
    }

    @Test("QB-APP-001 AC-55: com a leitura atrasada, a declaração cessa na mesma atualização")
    func theDeclarationStopsWhenTheReadingArrives() {
        let arrivedAt = Journey.readAt.addingTimeInterval(320)
        let presenter = Journey.openPanel(over: Journey.state())
        #expect(presenter.panelContent(at: arrivedAt).cadenceLine == Self.deferredLine)

        presenter.receive(
            Journey.state(
                deferralDeadline: arrivedAt.addingTimeInterval(270),
                readAt: arrivedAt,
                cycleID: 2,
                readSequence: 2
            )
        )
        let content = presenter.panelContent(at: arrivedAt.addingTimeInterval(30))

        #expect(content.cadenceLine == Self.baseLine)
        #expect(content.situation.contains("há menos de um minuto"))
        for line in Journey.allStrings(of: content) {
            #expect(!line.lowercased().contains("adiad"), "resíduo de adiamento no painel: \(line)")
            #expect(!line.lowercased().contains("atraso"), "resíduo de adiamento no painel: \(line)")
        }
    }

    @Test("QB-APP-001 AC-56: abrir, fechar e reabrir não encerra a declaração, e o intervalo base não a nega")
    func reopeningThePanelDoesNotEndTheDeclaration() {
        let observed = Journey.readAt.addingTimeInterval(300)
        let presenter = Journey.openPanel(over: Journey.state())

        let firstOpening = presenter.panelContent(at: observed)
        presenter.panelDidClose()
        presenter.panelDidOpen()
        let secondOpening = presenter.panelContent(at: observed.addingTimeInterval(1))

        #expect(firstOpening.cadenceLine == Self.deferredLine)
        #expect(secondOpening.cadenceLine == Self.deferredLine)
        #expect(presenter.state.cycle?.cadence.nature == .base, "o intervalo fornecido é o de ritmo base")
    }
}

@MainActor
@Suite("Pontualidade do limiar de adiamento")
struct DeferralPunctualityTests {
    private static let budget: TimeInterval = 1

    private static func state(deadline: Date, readAt: Date) -> QuotaState {
        Journey.state(deferralDeadline: deadline, readAt: readAt)
    }

    @Test("QB-API-001 AC-45: com observador presente, o cruzamento é publicado em até 1 segundo")
    func theCrossingIsPublishedWithinASecondWhileObserved() async throws {
        let ledger = RenderLedger()
        let now = Date()
        let deadline = now.addingTimeInterval(0.25)
        let presenter = IndicatorPresenter(
            provider: RecordingQuotaStateProvider(),
            reduceMotion: { .off },
            requestRender: ledger.record
        )
        presenter.receive(Self.state(deadline: deadline, readAt: now))
        presenter.panelDidOpen()
        #expect(presenter.armedDeferralThreshold == deadline)

        try await Task.sleep(for: .milliseconds(900))
        let crossings = ledger.recorded

        #expect(crossings.count == 1, "o limiar disparou \(crossings.count) vezes")
        for crossing in crossings {
            #expect(crossing >= deadline, "o limiar disparou antes do prazo")
            #expect(crossing.timeIntervalSince(deadline) <= Self.budget)
        }
        #expect(presenter.panelContent(at: Date()).cadenceLine?.contains("adiada pelo sistema") == true)
    }

    @Test("QB-API-001 AC-45: com o painel fechado nada fica armado e nada dispara")
    func nothingIsArmedWhileThePanelIsClosed() async throws {
        let ledger = RenderLedger()
        let now = Date()
        let presenter = IndicatorPresenter(
            provider: RecordingQuotaStateProvider(),
            reduceMotion: { .off },
            requestRender: ledger.record
        )
        presenter.receive(Self.state(deadline: now.addingTimeInterval(0.25), readAt: now))

        #expect(presenter.armedDeferralThreshold == nil)
        try await Task.sleep(for: .milliseconds(900))
        #expect(ledger.recorded.isEmpty, "o limiar cobrou atividade do repouso")
    }

    @Test("QB-API-001 AC-45: fechar o painel desarma o limiar antes de ele vencer")
    func closingThePanelDisarmsTheThreshold() async throws {
        let ledger = RenderLedger()
        let now = Date()
        let presenter = IndicatorPresenter(
            provider: RecordingQuotaStateProvider(),
            reduceMotion: { .off },
            requestRender: ledger.record
        )
        presenter.receive(Self.state(deadline: now.addingTimeInterval(0.4), readAt: now))
        presenter.panelDidOpen()
        presenter.panelDidClose()

        #expect(presenter.armedDeferralThreshold == nil)
        try await Task.sleep(for: .milliseconds(900))
        #expect(ledger.recorded.isEmpty)
    }

    @Test("QB-API-001 AC-45: um prazo já vencido não arma nada, porque não há cruzamento a esperar")
    func aPassedDeadlineArmsNothing() {
        let now = Date()
        let presenter = IndicatorPresenter(
            provider: RecordingQuotaStateProvider(),
            clock: { now },
            reduceMotion: { .off }
        )
        presenter.receive(Self.state(deadline: now.addingTimeInterval(-1), readAt: now))
        presenter.panelDidOpen()

        #expect(presenter.armedDeferralThreshold == nil)
    }
}
