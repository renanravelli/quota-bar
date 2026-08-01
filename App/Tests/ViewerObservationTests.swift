import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

private enum Fixture {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)
    static let openedAt = readAt.addingTimeInterval(28 * 60)

    static func reading(under cadence: ScheduledNature) -> QuotaState {
        let interval: Duration = cadence == .idle ? .seconds(900) : .seconds(180)
        let snapshot = QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: Utilization(originPercent: 30),
                resetsAt: readAt.addingTimeInterval(3_600),
                status: .allowed
            ),
            sevenDay: WindowReading(utilization: nil, resetsAt: nil, status: .allowed),
            overallStatus: .allowed,
            nextResetAt: readAt.addingTimeInterval(3_600),
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
            cycle: TestCycle.scheduled(interval, nature: cadence),
            maxIdleCadenceSinceReading: .seconds(900),
            source: .primaryProbe
        )
    }

    @MainActor
    static func presenter(_ provider: RecordingQuotaStateProvider) -> IndicatorPresenter {
        IndicatorPresenter(provider: provider, clock: { openedAt }, reduceMotion: { .off })
    }
}

@MainActor
@Suite("Observação do painel e regime de cadência")
struct ViewerObservationTests {
    @Test("abrir o painel devolve a cadência ao ritmo base e o indicador continua em ready")
    func openingThePanelRestoresTheBaseCadenceWithoutChangingTheState() async {
        let provider = RecordingQuotaStateProvider()
        let presenter = Fixture.presenter(provider)
        let observation = Task { await presenter.observeStates() }
        defer { observation.cancel() }

        provider.emit(Fixture.reading(under: .idle))
        await Wait.until { presenter.state.cycle?.cadence.nature == .idle }
        #expect(presenter.indicatorText == "5h 30%")
        #expect(presenter.panelContent(at: Fixture.openedAt).cadenceLine == "Atualizando a cada 15 minutos — reduzido por ociosidade.")

        presenter.panelDidOpen()
        await Wait.until { await provider.viewerSignals == [true] }
        provider.emit(Fixture.reading(under: .base))
        await Wait.until { presenter.state.cycle?.cadence.nature == .base }

        #expect(await provider.viewerSignals == [true])
        #expect(presenter.panelContent(at: Fixture.openedAt).cadenceLine == "Atualizando a cada 3 minutos — ritmo base.")
        #expect(presenter.indicatorText == "5h 30%")
        if case .ready = presenter.indicator {} else {
            Issue.record("o indicador saiu de ready ao abrir o painel: \(presenter.indicator)")
        }
    }

    @Test("abrir o painel muda o regime de cadência e não pede leitura")
    func openingThePanelDoesNotAskForAReading() async {
        let provider = RecordingQuotaStateProvider()
        let presenter = Fixture.presenter(provider)

        presenter.panelDidOpen()
        await Wait.until { await provider.viewerSignals == [true] }

        #expect(await provider.refreshCount == 0)
    }

    @Test("fechar o painel devolve o regime de ociosidade")
    func closingThePanelReleasesTheRegime() async {
        let provider = RecordingQuotaStateProvider()
        let presenter = Fixture.presenter(provider)

        presenter.panelDidOpen()
        presenter.panelDidClose()
        await Wait.until { await provider.viewerSignals.count == 2 }

        #expect(await provider.viewerSignals == [true, false])
    }

    @Test("abrir e fechar repetidamente preserva a ordem dos sinais e não pede leitura")
    func repeatedOpeningPreservesTheOrderOfTheSignals() async {
        let provider = RecordingQuotaStateProvider()
        let presenter = Fixture.presenter(provider)

        for _ in 0..<10 {
            presenter.panelDidOpen()
            presenter.panelDidClose()
        }
        await Wait.until { await provider.viewerSignals.count == 20 }

        #expect(await provider.viewerSignals == Array(repeating: [true, false], count: 10).flatMap { $0 })
        #expect(await provider.refreshCount == 0)
    }
}
