import Foundation
import Testing

import QuotaBarCoreFixtures

@testable import QuotaBarCore

@Suite("Fronteira do provedor de estado")
struct QuotaStateProvidingTests {
    private static func state(percent: String) -> QuotaState {
        QuotaState(
            credentialPresent: true,
            snapshot: TestSnapshot.make(
                fiveHourPercent: percent,
                sevenDayPercent: nil,
                bindingWindow: .window(.fiveHour)
            ),
            lastAttempt: .succeeded(at: TestSnapshot.readAt),
            cycle: TestCycle.scheduled(.seconds(180), nature: .base),
            maxIdleCadenceSinceReading: .seconds(180),
            source: .primaryProbe
        )
    }

    private static func text(for state: QuotaState) -> String {
        var latch = StaleLatch()
        let resolved = IndicatorStateResolver.resolve(
            state: state,
            latch: &latch,
            now: TestSnapshot.readAt.addingTimeInterval(60)
        )
        return IndicatorTextFormatter.text(for: resolved)
    }

    @Test("AC-21: o estado mais recente fornecido chega a quem consome o provedor")
    func providerDeliversEachState() async {
        let provider = ControlledQuotaStateProvider()
        var received: [String] = []

        provider.emit(Self.state(percent: "40"))
        provider.emit(Self.state(percent: "55"))
        provider.finish()

        for await state in provider.states {
            received.append(Self.text(for: state))
        }

        #expect(received == ["5h 40%", "5h 55%"])
    }

    @Test("AC-21: o consumo acompanha o fornecimento sem exigir sondagem")
    func consumerSeesUpdateWithoutPolling() async {
        let provider = ControlledQuotaStateProvider()
        var iterator = provider.states.makeAsyncIterator()

        provider.emit(Self.state(percent: "40"))
        let first = await iterator.next()

        provider.emit(Self.state(percent: "55"))
        let second = await iterator.next()

        #expect(first.map(Self.text) == "5h 40%")
        #expect(second.map(Self.text) == "5h 55%")
    }

    @Test("AC-21: o provedor registra pedidos explícitos de atualização")
    func providerRecordsRefreshRequests() async {
        let provider = ControlledQuotaStateProvider()

        await provider.refreshNow()
        await provider.refreshNow()

        #expect(await provider.refreshCount() == 2)
    }

    @Test("AC-21: o contrato do provedor é consumível por trás do protocolo")
    func providerIsUsableThroughTheProtocol() async {
        let provider: any QuotaStateProviding = ControlledQuotaStateProvider()

        guard let controlled = provider as? ControlledQuotaStateProvider else {
            Issue.record("provedor de teste não conforma ao protocolo")
            return
        }
        controlled.emit(Self.state(percent: "33"))
        controlled.finish()

        var received: [String] = []
        for await state in provider.states {
            received.append(Self.text(for: state))
        }

        #expect(received == ["5h 33%"])
    }
}
