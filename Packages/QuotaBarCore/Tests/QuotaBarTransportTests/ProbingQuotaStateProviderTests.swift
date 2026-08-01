import Foundation
import QuotaBarCore
import QuotaBarCoreFixtures
import Testing
import os

@testable import QuotaBarTransport

struct Publication: Sendable {
    let state: QuotaState
    let at: Date
}

private final class StateCollector: Sendable {
    private let published = OSAllocatedUnfairLock(initialState: [Publication]())

    var all: [Publication] {
        published.withLock { $0 }
    }

    var latest: QuotaState? {
        all.last?.state
    }

    func consume(_ states: AsyncStream<QuotaState>, clock: ControlledClock) async {
        for await state in states {
            let stamped = Publication(state: state, at: clock.now)
            published.withLock { $0.append(stamped) }
        }
    }
}

final class ProviderHarness {
    static let start = Date(timeIntervalSince1970: 1_700_000_000)

    let clock = ControlledClock(at: start)
    let transport: RecordingTransport
    let claudeCode: StubClaudeCode
    let power = SilentPowerEvents()
    let provider: ProbingQuotaStateProvider

    private let collector = StateCollector()
    private let collecting: Task<Void, Never>
    private let lifecycleRunning: Task<Void, Never>
    private let running: Task<Void, Never>

    var latest: QuotaState? { collector.latest }

    var published: [QuotaState] { collector.all.map(\.state) }

    var publications: [Publication] { collector.all }

    init(
        responses: [ProbeHTTPResponse],
        credentials: any CredentialStoring = StubCredentials.configured,
        version: String? = "2.1.220 (Claude Code)",
        store: any QuotaSnapshotStoring = InMemorySnapshotStore()
    ) {
        transport = RecordingTransport(responses)
        claudeCode = StubClaudeCode(version: version)

        let lifecycle = ProbeLifecycle(observing: power, activity: InertActivity(), time: clock)
        provider = ProbingQuotaStateProvider(
            probe: QuotaProbe(transport: transport, credentials: credentials),
            credentials: credentials,
            environment: claudeCode,
            lifecycle: lifecycle,
            store: store,
            time: clock,
            waiter: clock,
            jitter: { 1 }
        )

        let states = provider.states
        let collector = collector
        let clock = clock
        collecting = Task { await collector.consume(states, clock: clock) }
        lifecycleRunning = Task { await lifecycle.run() }
        running = Task { [provider] in await provider.run() }
    }

    deinit {
        power.finish()
        running.cancel()
        lifecycleRunning.cancel()
        collecting.cancel()
    }

    @discardableResult
    func waitForProbes(_ count: Int) async -> Bool {
        await waitUntil { [transport] in transport.sentCount >= count }
    }

    func waitUntil(_ condition: @Sendable () -> Bool) async -> Bool {
        for _ in 0..<600 {
            if condition() { await settle(); return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func settle() async {
        try? await Task.sleep(for: .milliseconds(40))
    }
}

@Suite("Provedor real de estado de cota")
struct ProbingQuotaStateProviderTests {
    @Test("AC-5: a leitura bem-sucedida vira estado publicado, em ritmo base e fonte primária")
    func aReadingBecomesPublishedState() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()])

        #expect(await harness.waitForProbes(1))

        let state = try #require(harness.latest)
        #expect(state.credentialPresent)
        #expect(state.snapshot?.readSequence == 1)
        #expect(state.snapshot?.source == .primaryProbe)
        #expect(state.source == .primaryProbe)
        #expect(state.cycle?.cadence.nature == .base)
        #expect(state.cycle?.cadence.interval == ProbePlanner.baseInterval)
        if case .succeeded = state.lastAttempt {} else { Issue.record("a tentativa deveria ter tido sucesso") }
    }

    @Test("AC-17 e AC-19: passar a observar muda o regime e não provoca leitura")
    func observingChangesTheRegimeWithoutReading() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading(), CannedResponse.reading()])
        #expect(await harness.waitForProbes(1))

        for _ in 0..<10 {
            await harness.provider.setViewerObserving(true)
            await harness.provider.setViewerObserving(false)
        }
        await harness.settle()

        #expect(harness.transport.sentCount == 1)
        #expect(harness.latest?.cycle?.cadence.interval == ProbePlanner.baseInterval)
    }

    @Test("AC-36 de QB-APP-001: com o observador presente a cadência volta ao ritmo base")
    func theViewerRestoresTheBaseCadence() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading(), CannedResponse.reading()])
        #expect(await harness.waitForProbes(1))

        harness.clock.advance(by: 180)
        #expect(await harness.waitForProbes(2))
        #expect(harness.latest?.cycle?.cadence.nature == .idle)

        await harness.provider.setViewerObserving(true)
        await harness.settle()

        #expect(harness.latest?.cycle?.cadence.nature == .base)
        #expect(harness.latest?.cycle?.cadence.interval == ProbePlanner.baseInterval)
        #expect(harness.transport.sentCount == 2)
    }

    @Test("REQ-11: pedir leitura agora provoca exatamente uma leitura, respeitado o piso")
    func refreshNowAsksForExactlyOneReading() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading(), CannedResponse.reading()])
        #expect(await harness.waitForProbes(1))

        await harness.provider.refreshNow()
        await harness.settle()
        #expect(harness.transport.sentCount == 1)

        harness.clock.advance(by: 60)
        #expect(await harness.waitForProbes(2))
        #expect(harness.transport.sentCount == 2)
    }

    @Test("AC-28: recusa de credencial interrompe as leituras periódicas até ação do usuário")
    func refusalStopsPeriodicProbing() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.rejected(), CannedResponse.reading()])
        #expect(await harness.waitForProbes(1))

        harness.clock.advance(by: 3_600)
        await harness.settle()

        #expect(harness.transport.sentCount == 1)
        #expect(harness.latest?.lastAttempt == .failed(.credentialRejected))
        #expect(harness.latest?.cycle == nil)

        await harness.provider.refreshNow()
        #expect(await harness.waitForProbes(2))
        #expect(harness.latest?.cycle != nil)
    }

    @Test("AC-3: sem Claude Code descoberto, nenhuma leitura é realizada")
    func withoutClaudeCodeNothingIsRead() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()], version: nil)
        await harness.settle()

        harness.clock.advance(by: 3_600)
        await harness.settle()

        #expect(harness.transport.sentCount == 0)
        #expect(harness.latest?.cycle == nil)
        #expect(harness.latest?.source == nil)
    }

    @Test("AC-49 de QB-APP-001: sem Claude Code, a pendência é publicada com a credencial configurada")
    func theClaudeCodePendencyIsPublished() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()], version: nil)
        await harness.settle()

        let state = try #require(harness.latest)
        #expect(state.credentialPresent)
        #expect(state.pendencies == [.claudeCode])
        #expect(state.lastAttempt == .failed(.claudeCodeNotFound))
        #expect(harness.transport.sentCount == 0)
    }

    @Test("AC-51 de QB-APP-001: sem credencial e sem Claude Code, as duas pendências são publicadas juntas")
    func bothPendenciesArePublishedTogether() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            credentials: StubCredentials.failing(.itemNotFound),
            version: nil
        )
        await harness.settle()

        #expect(harness.latest?.pendencies == [.credential, .claudeCode])
        #expect(harness.transport.sentCount == 0)
    }

    @Test("AC-2: instalar o Claude Code em execução limpa a pendência e a leitura volta a acontecer")
    func installingClaudeCodeClearsThePendency() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()], version: nil)
        await harness.settle()
        #expect(harness.latest?.pendencies == [.claudeCode])

        harness.claudeCode.install(version: "2.1.220 (Claude Code)")
        harness.clock.advance(by: 180)
        #expect(await harness.waitForProbes(1))

        #expect(harness.latest?.pendencies.isEmpty == true)
        #expect(harness.latest?.source == .primaryProbe)
    }

    @Test("AC-12: sem credencial configurada, o estado não afirma cadência nem fonte")
    func withoutCredentialNothingIsAffirmed() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            credentials: StubCredentials.failing(.itemNotFound)
        )
        await harness.settle()
        harness.clock.advance(by: 3_600)
        await harness.settle()

        let state = try #require(harness.latest)
        #expect(!state.credentialPresent)
        #expect(state.cycle == nil)
        #expect(state.source == nil)
        #expect(state.snapshot == nil)
        #expect(harness.transport.sentCount == 0)
    }

    @Test("Estados: sem credencial o provedor fica Impedido, e configurar a credencial devolve a sondagem")
    func configuringAfterAnEmptyFirstRunResumesProbing() async throws {
        let credentials = SwitchableCredentials()
        let harness = ProviderHarness(responses: [CannedResponse.reading()], credentials: credentials)
        await harness.settle()

        #expect(harness.latest?.pendencies == [.credential])
        #expect(harness.transport.sentCount == 0)

        _ = await credentials.store(try #require(SubscriptionToken(pasted: StubCredentials.pasted)))
        harness.clock.advance(by: 180)

        #expect(await harness.waitForProbes(1))
        #expect(harness.latest?.credentialPresent == true)
        #expect(harness.latest?.pendencies.isEmpty == true)
        #expect(harness.latest?.snapshot != nil)
    }

    @Test("SEC REQ-7: gravada a credencial pela superfície, o pedido do usuário lê sem esperar o ciclo")
    func savingTheCredentialProbesWithoutWaitingForTheNextCycle() async throws {
        let credentials = SwitchableCredentials()
        let harness = ProviderHarness(responses: [CannedResponse.reading()], credentials: credentials)
        await harness.settle()
        #expect(harness.transport.sentCount == 0)

        _ = await credentials.store(try #require(SubscriptionToken(pasted: StubCredentials.pasted)))
        await harness.provider.refreshNow()

        #expect(await harness.waitForProbes(1))
        #expect(harness.latest?.snapshot != nil)
        #expect(harness.latest?.cycle?.cadence.nature == .base)
    }

    @Test("SEC REQ-15: falha de Keychain publica motivo próprio, distinto de recusa")
    func keychainFailureHasItsOwnReason() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            credentials: StubCredentials.failing(.authorizationDenied)
        )
        await harness.settle()

        #expect(harness.latest?.lastAttempt == .failed(.credentialUnreadable))
        #expect(harness.transport.sentCount == 0)
    }

    @Test("AC-22: estrangulamento sem dado é falha de comunicação e amplia a cadência")
    func throttlingWidensTheCadence() async throws {
        let harness = ProviderHarness(responses: [
            CannedResponse.reading(),
            CannedResponse.throttled(retryAfterSeconds: 600)
        ])
        #expect(await harness.waitForProbes(1))

        harness.clock.advance(by: 180)
        #expect(await harness.waitForProbes(2))

        #expect(harness.latest?.lastAttempt == .failed(.communicationFailure))
        #expect(harness.latest?.cycle?.cadence.nature == .widenedByFailure)
        #expect(harness.latest?.cycle?.cadence.interval == .seconds(600))
    }

    @Test("AC-21: cota esgotada com dado é leitura bem-sucedida e não amplia a cadência")
    func exhaustedQuotaIsAReading() async throws {
        let harness = ProviderHarness(responses: [
            CannedResponse.reading(),
            CannedResponse.reading(.exhausted, status: 429)
        ])
        #expect(await harness.waitForProbes(1))

        harness.clock.advance(by: 180)
        #expect(await harness.waitForProbes(2))

        #expect(harness.latest?.snapshot?.readSequence == 2)
        #expect(harness.latest?.cycle?.cadence.nature != .widenedByFailure)
        if case .succeeded = harness.latest?.lastAttempt {} else {
            Issue.record("cota esgotada com dado é leitura bem-sucedida")
        }
    }

    @Test("ADR-005: suspensa a máquina no meio do preparo, a sonda é recusada e não conta como tentativa")
    func aSuspensionWhilePreparingTheProbeRefusesIt() async throws {
        let credentials = GatedCredentials(blockingCall: 2)
        let harness = ProviderHarness(responses: [CannedResponse.reading()], credentials: credentials)
        #expect(await harness.waitUntil { credentials.parked })

        harness.power.send(.willSleep)
        await harness.settle()
        credentials.open()
        await harness.settle()

        #expect(harness.transport.sentCount == 0)
        #expect(harness.latest?.lastAttempt == .inProgress)
        #expect(harness.latest?.cycle?.cadence.nature == .base)
    }

    @Test("AC-20, AC-43 e AC-44: durante a espera, cinco minutos declaram adiamento e quatro não")
    func theConditionIsObservedDuringTheWaitAndNotAfterTheReading() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()])
        #expect(await harness.waitForProbes(1))

        let published = try #require(harness.latest)
        let readAt = ProviderHarness.start
        var latch = DeferralLatch()

        #expect(published.cycle?.cadence.nature == .base)
        #expect(published.cadence(at: readAt.addingTimeInterval(240), latch: &latch)?.nature == .base)
        #expect(
            published.cadence(at: readAt.addingTimeInterval(300), latch: &latch)?.nature == .deferredBySystem
        )
        #expect(published.maxIdleCadenceSinceReading == published.cycle?.cadence.interval)
        #expect(harness.transport.sentCount == 1)
    }

    @Test("AC-37: nenhum estado publicado durante a suspensão e a retomada declara adiamento")
    func sleepIsNeverPublishedAsDeferral() async throws {
        var afterTheSleep = UnifiedRateLimitHeaderFixture.complete
        afterTheSleep.fiveHourUtilization = "0.8125"

        let harness = ProviderHarness(responses: [
            CannedResponse.reading(),
            CannedResponse.reading(afterTheSleep)
        ])
        #expect(await harness.waitForProbes(1))

        harness.power.send(.willSleep)
        await harness.settle()
        harness.clock.advance(by: 8 * 3_600)
        await harness.settle()
        #expect(harness.transport.sentCount == 1)

        harness.power.send(.didWake)
        #expect(await harness.waitForProbes(2))

        var latch = DeferralLatch()
        let natures = harness.publications.compactMap { $0.state.cadence(at: $0.at, latch: &latch)?.nature }

        #expect(harness.latest?.cycle?.cadence.nature == .base)
        #expect(!natures.isEmpty)
        #expect(natures.allSatisfy { $0 != .deferredBySystem })
    }

    @Test("AC-38 e AC-52: depois da retomada, cinco minutos de espera voltam a ser adiamento e quatro não")
    func deferralHoldsAgainAfterTheMachineWakesUp() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()])
        #expect(await harness.waitForProbes(1))

        harness.power.send(.willSleep)
        await harness.settle()
        harness.clock.advance(by: 10)
        harness.power.send(.didWake)
        await harness.settle()
        #expect(harness.transport.sentCount == 1)

        let wake = ProviderHarness.start.addingTimeInterval(10)
        let resumed = try #require(harness.latest)
        var latch = DeferralLatch()

        #expect(resumed.cycle?.cadence.nature == .base)
        #expect(resumed.cadence(at: wake.addingTimeInterval(240), latch: &latch)?.nature == .base)
        #expect(
            resumed.cadence(at: wake.addingTimeInterval(300), latch: &latch)?.nature == .deferredBySystem
        )
    }

    @Test("AC-39: leitura pontual sob ociosidade não vira adiamento quando o observador chega no fim do ciclo")
    func aPunctualReadingIsNotDeferredAfterTheViewerRestoresTheBaseCadence() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()])
        #expect(await harness.waitForProbes(1))

        var probes = 1
        for interval in [180.0, 360.0, 720.0] {
            harness.clock.advance(by: interval)
            probes += 1
            #expect(await harness.waitForProbes(probes))
        }
        #expect(harness.latest?.cycle?.cadence.interval == ProbePlanner.idleCeiling)

        harness.clock.advance(by: 780)
        await harness.provider.setViewerObserving(true)
        await harness.settle()
        #expect(harness.transport.sentCount == probes)

        harness.clock.advance(by: 120)
        #expect(await harness.waitForProbes(probes + 1))

        #expect(harness.latest?.cycle?.cadence.nature == .base)
    }

    @Test("AC-7: janela limitante ausente é publicada como indisponível, nunca deduzida")
    func absentFieldsArePublishedAsUnavailable() async throws {
        var fixture = UnifiedRateLimitHeaderFixture.complete
        fixture.representativeClaim = nil
        fixture.sevenDayReset = nil

        let harness = ProviderHarness(responses: [CannedResponse.reading(fixture)])
        #expect(await harness.waitForProbes(1))

        let state = try #require(harness.latest)
        #expect(state.snapshot?.bindingWindow == nil)
        #expect(state.unavailableFields.contains(.bindingWindow))
        #expect(state.unavailableFields.contains(.resetAt(.sevenDay)))
        #expect(!state.unavailableFields.contains(.utilization(.fiveHour)))
    }

    @Test("ADR-005: nenhuma sonda enquanto a máquina dorme; ao acordar volta ao ritmo base")
    func suspensionStopsProbingAndWakeResumesIt() async throws {
        let harness = ProviderHarness(responses: [
            CannedResponse.reading(),
            CannedResponse.reading(),
            CannedResponse.reading()
        ])
        #expect(await harness.waitForProbes(1))

        harness.power.send(.willSleep)
        await harness.settle()
        harness.clock.advance(by: 7_200)
        await harness.settle()
        #expect(harness.transport.sentCount == 1)

        let publishedBeforeWake = harness.published.count
        harness.power.send(.didWake)
        #expect(await harness.waitForProbes(2))

        let afterWake = harness.published.dropFirst(publishedBeforeWake)
        #expect(afterWake.contains { $0.cycle?.cadence.nature == .base })
    }
}
