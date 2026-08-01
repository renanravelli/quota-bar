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
    private let exhausted = OSAllocatedUnfairLock(initialState: false)

    var all: [Publication] {
        published.withLock { $0 }
    }

    var latest: QuotaState? {
        all.last?.state
    }

    var sawTheStreamFinish: Bool {
        exhausted.withLock { $0 }
    }

    func consume(_ states: AsyncStream<QuotaState>, clock: ControlledClock) async {
        for await state in states {
            let stamped = Publication(state: state, at: clock.now)
            published.withLock { $0.append(stamped) }
        }
        exhausted.withLock { $0 = true }
    }
}

final class ProviderHarness {
    static let start = Date(timeIntervalSince1970: 1_700_000_000)

    let clock = ControlledClock(at: start)
    let transport: RecordingTransport
    let claudeCode: StubClaudeCode
    let power = SilentPowerEvents()
    let lifecycle: ProbeLifecycle
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

        lifecycle = ProbeLifecycle(observing: power, activity: InertActivity(), time: clock)
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
        lifecycleRunning = Task { [lifecycle] in await lifecycle.run() }
        running = Task { [provider] in await provider.run() }
    }

    deinit {
        power.finish()
        running.cancel()
        lifecycleRunning.cancel()
        collecting.cancel()
        clock.releaseWaiters()
    }

    func waitForReading(sequence: UInt64) async -> Bool {
        await waitForState { $0.snapshot?.readSequence == sequence }
    }

    func waitForState(_ satisfies: @Sendable (QuotaState) -> Bool) async -> Bool {
        await waitUntil { [collector] in collector.latest.map(satisfies) ?? false }
    }

    func waitForPublications(_ count: Int) async -> Bool {
        await waitUntil { [collector] in collector.all.count >= count }
    }

    func waitUntilProbingRests() async -> Bool {
        await waitUntil { [clock] in clock.isAwaitingFutureDeadline }
    }

    func waitUntilProbingIsSuspended() async -> Bool {
        await waitUntil { [lifecycle] in await !lifecycle.allowsProbing }
    }

    func cancelRun() {
        running.cancel()
    }

    func waitUntilStatesFinish() async -> Bool {
        await waitUntil { [collector] in collector.sawTheStreamFinish }
    }

    func waitUntil(_ condition: @Sendable () async -> Bool) async -> Bool {
        for _ in 0..<600 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }
}

@Suite("Provedor real de estado de cota")
struct ProbingQuotaStateProviderTests {
    @Test("a leitura bem-sucedida vira estado publicado, em ritmo base e fonte primária")
    func aReadingBecomesPublishedState() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()])

        #expect(await harness.waitForReading(sequence: 1))

        let state = try #require(harness.latest)
        #expect(state.credentialPresent)
        #expect(state.snapshot?.readSequence == 1)
        #expect(state.snapshot?.source == .primaryProbe)
        #expect(state.source == .primaryProbe)
        #expect(state.cycle?.cadence.nature == .base)
        #expect(state.cycle?.cadence.interval == ProbePlanner.baseInterval)
        if case .succeeded = state.lastAttempt {} else { Issue.record("a tentativa deveria ter tido sucesso") }
    }

    @Test("passar a observar muda o regime e não provoca leitura")
    func observingChangesTheRegimeWithoutReading() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading(), CannedResponse.reading()])
        #expect(await harness.waitForReading(sequence: 1))

        for _ in 0..<10 {
            await harness.provider.setViewerObserving(true)
            await harness.provider.setViewerObserving(false)
        }
        #expect(await harness.waitUntilProbingRests())

        #expect(harness.transport.sentCount == 1)
        #expect(harness.latest?.cycle?.cadence.interval == ProbePlanner.baseInterval)
    }

    @Test("com o observador presente a cadência volta ao ritmo base")
    func theViewerRestoresTheBaseCadence() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading(), CannedResponse.reading()])
        #expect(await harness.waitForReading(sequence: 1))

        harness.clock.advance(by: 180)
        #expect(await harness.waitForReading(sequence: 2))
        #expect(harness.latest?.cycle?.cadence.nature == .idle)

        await harness.provider.setViewerObserving(true)
        #expect(await harness.waitForState { $0.cycle?.cadence.nature == .base })
        #expect(await harness.waitUntilProbingRests())

        #expect(harness.latest?.cycle?.cadence.interval == ProbePlanner.baseInterval)
        #expect(harness.transport.sentCount == 2)
    }

    @Test("pedir leitura agora provoca exatamente uma leitura, respeitado o piso")
    func refreshNowAsksForExactlyOneReading() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading(), CannedResponse.reading()])
        #expect(await harness.waitForReading(sequence: 1))

        await harness.provider.refreshNow()
        #expect(await harness.waitUntilProbingRests())
        #expect(harness.transport.sentCount == 1)

        harness.clock.advance(by: 60)
        #expect(await harness.waitForReading(sequence: 2))
        #expect(harness.transport.sentCount == 2)
    }

    @Test("recusa de credencial interrompe as leituras periódicas até ação do usuário")
    func refusalStopsPeriodicProbing() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.rejected(), CannedResponse.reading()])
        #expect(await harness.waitForState { $0.lastAttempt == .failed(.credentialRejected) })

        harness.clock.advance(by: 3_600)
        #expect(await harness.waitUntilProbingRests())

        #expect(harness.transport.sentCount == 1)
        #expect(harness.latest?.cycle == nil)

        await harness.provider.refreshNow()
        #expect(await harness.waitForReading(sequence: 1))
        #expect(harness.transport.sentCount == 2)
        #expect(harness.latest?.cycle != nil)
    }

    @Test("sem Claude Code descoberto, nenhuma leitura é realizada")
    func withoutClaudeCodeNothingIsRead() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()], version: nil)
        #expect(await harness.waitForState { $0.lastAttempt == .failed(.claudeCodeNotFound) })
        #expect(await harness.waitUntilProbingRests())

        harness.clock.advance(by: 3_600)
        #expect(await harness.waitUntilProbingRests())

        #expect(harness.transport.sentCount == 0)
        #expect(harness.latest?.cycle == nil)
        #expect(harness.latest?.source == nil)
    }

    @Test("sem Claude Code, a pendência é publicada com a credencial configurada")
    func theClaudeCodePendencyIsPublished() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()], version: nil)
        #expect(await harness.waitForState { $0.pendencies == [.claudeCode] })

        let state = try #require(harness.latest)
        #expect(state.credentialPresent)
        #expect(state.lastAttempt == .failed(.claudeCodeNotFound))
        #expect(harness.transport.sentCount == 0)
    }

    @Test("sem credencial e sem Claude Code, as duas pendências são publicadas juntas")
    func bothPendenciesArePublishedTogether() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            credentials: StubCredentials.failing(.itemNotFound),
            version: nil
        )
        #expect(await harness.waitForState { $0.pendencies == [.credential, .claudeCode] })

        #expect(harness.transport.sentCount == 0)
    }

    @Test("instalar o Claude Code em execução limpa a pendência e a leitura volta a acontecer")
    func installingClaudeCodeClearsThePendency() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()], version: nil)
        #expect(await harness.waitForState { $0.pendencies == [.claudeCode] })
        #expect(await harness.waitUntilProbingRests())

        harness.claudeCode.install(version: "2.1.220 (Claude Code)")
        harness.clock.advance(by: 180)
        #expect(await harness.waitForReading(sequence: 1))

        #expect(harness.latest?.pendencies.isEmpty == true)
        #expect(harness.latest?.source == .primaryProbe)
    }

    @Test("sem credencial configurada, o estado não afirma cadência nem fonte")
    func withoutCredentialNothingIsAffirmed() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            credentials: StubCredentials.failing(.itemNotFound)
        )
        #expect(await harness.waitForState { $0.pendencies == [.credential] })
        #expect(await harness.waitUntilProbingRests())

        harness.clock.advance(by: 3_600)
        #expect(await harness.waitUntilProbingRests())

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
        #expect(await harness.waitForState { $0.pendencies == [.credential] })
        #expect(await harness.waitUntilProbingRests())

        #expect(harness.transport.sentCount == 0)

        _ = await credentials.store(try #require(SubscriptionToken(pasted: StubCredentials.pasted)))
        harness.clock.advance(by: 180)

        #expect(await harness.waitForReading(sequence: 1))
        #expect(harness.latest?.credentialPresent == true)
        #expect(harness.latest?.pendencies.isEmpty == true)
        #expect(harness.latest?.snapshot != nil)
    }

    @Test("gravada a credencial pela superfície, o pedido do usuário lê sem esperar o ciclo")
    func savingTheCredentialProbesWithoutWaitingForTheNextCycle() async throws {
        let credentials = SwitchableCredentials()
        let harness = ProviderHarness(responses: [CannedResponse.reading()], credentials: credentials)
        #expect(await harness.waitForState { $0.pendencies == [.credential] })
        #expect(await harness.waitUntilProbingRests())
        #expect(harness.transport.sentCount == 0)

        _ = await credentials.store(try #require(SubscriptionToken(pasted: StubCredentials.pasted)))
        await harness.provider.refreshNow()

        #expect(await harness.waitForReading(sequence: 1))
        #expect(harness.latest?.snapshot != nil)
        #expect(harness.latest?.cycle?.cadence.nature == .base)
    }

    @Test("falha de Keychain publica motivo próprio, distinto de recusa")
    func keychainFailureHasItsOwnReason() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            credentials: StubCredentials.failing(.authorizationDenied)
        )
        #expect(await harness.waitForState { $0.lastAttempt == .failed(.credentialUnreadable) })

        #expect(harness.transport.sentCount == 0)
    }

    @Test("estrangulamento sem dado é falha de comunicação e amplia a cadência")
    func throttlingWidensTheCadence() async throws {
        let harness = ProviderHarness(responses: [
            CannedResponse.reading(),
            CannedResponse.throttled(retryAfterSeconds: 600)
        ])
        #expect(await harness.waitForReading(sequence: 1))

        harness.clock.advance(by: 180)
        #expect(await harness.waitForState { $0.lastAttempt == .failed(.communicationFailure) })

        #expect(harness.transport.sentCount == 2)
        #expect(harness.latest?.cycle?.cadence.nature == .widenedByFailure)
        #expect(harness.latest?.cycle?.cadence.interval == .seconds(600))
    }

    @Test("cota esgotada com dado é leitura bem-sucedida e não amplia a cadência")
    func exhaustedQuotaIsAReading() async throws {
        let harness = ProviderHarness(responses: [
            CannedResponse.reading(),
            CannedResponse.reading(.exhausted, status: 429)
        ])
        #expect(await harness.waitForReading(sequence: 1))

        harness.clock.advance(by: 180)
        #expect(await harness.waitForReading(sequence: 2))

        #expect(harness.latest?.cycle?.cadence.nature != .widenedByFailure)
        if case .succeeded = harness.latest?.lastAttempt {} else {
            Issue.record("cota esgotada com dado é leitura bem-sucedida")
        }
    }

    @Test("suspensa a máquina no meio do preparo, a sonda é recusada e não conta como tentativa")
    func aSuspensionWhilePreparingTheProbeRefusesIt() async throws {
        let credentials = GatedCredentials(blockingCall: 2)
        let harness = ProviderHarness(responses: [CannedResponse.reading()], credentials: credentials)
        #expect(await harness.waitUntil { credentials.parked })

        harness.power.send(.willSleep)
        #expect(await harness.waitUntilProbingIsSuspended())

        credentials.open()
        #expect(await harness.waitForState { $0.cycle?.cadence.nature == .base })
        #expect(await harness.waitUntilProbingRests())

        #expect(harness.transport.sentCount == 0)
        #expect(harness.latest?.lastAttempt == .inProgress)
    }

    @Test("durante a espera, cinco minutos declaram adiamento e quatro não")
    func theConditionIsObservedDuringTheWaitAndNotAfterTheReading() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()])
        #expect(await harness.waitForReading(sequence: 1))

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

    @Test("nenhum estado publicado durante a suspensão e a retomada declara adiamento")
    func sleepIsNeverPublishedAsDeferral() async throws {
        var afterTheSleep = UnifiedRateLimitHeaderFixture.complete
        afterTheSleep.fiveHourUtilization = "0.8125"

        let harness = ProviderHarness(responses: [
            CannedResponse.reading(),
            CannedResponse.reading(afterTheSleep)
        ])
        #expect(await harness.waitForReading(sequence: 1))

        harness.power.send(.willSleep)
        #expect(await harness.waitUntilProbingIsSuspended())

        harness.clock.advance(by: 8 * 3_600)
        #expect(await harness.waitUntilProbingRests())
        #expect(harness.transport.sentCount == 1)

        harness.power.send(.didWake)
        #expect(await harness.waitForReading(sequence: 2))

        var latch = DeferralLatch()
        let natures = harness.publications.compactMap { $0.state.cadence(at: $0.at, latch: &latch)?.nature }

        #expect(harness.latest?.cycle?.cadence.nature == .base)
        #expect(!natures.isEmpty)
        #expect(natures.allSatisfy { $0 != .deferredBySystem })
    }

    @Test("depois da retomada, cinco minutos de espera voltam a ser adiamento e quatro não")
    func deferralHoldsAgainAfterTheMachineWakesUp() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()])
        #expect(await harness.waitForReading(sequence: 1))

        let cycleBeforeTheSleep = try #require(harness.latest?.cycle?.id)
        harness.power.send(.willSleep)
        #expect(await harness.waitUntilProbingIsSuspended())

        harness.clock.advance(by: 10)
        harness.power.send(.didWake)
        #expect(await harness.waitForState { $0.cycle?.id != cycleBeforeTheSleep })
        #expect(await harness.waitUntilProbingRests())
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

    @Test("leitura pontual sob ociosidade não vira adiamento quando o observador chega no fim do ciclo")
    func aPunctualReadingIsNotDeferredAfterTheViewerRestoresTheBaseCadence() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.reading()])
        #expect(await harness.waitForReading(sequence: 1))

        var readings: UInt64 = 1
        for interval in [180.0, 360.0, 720.0] {
            harness.clock.advance(by: interval)
            readings += 1
            #expect(await harness.waitForReading(sequence: readings))
        }
        #expect(harness.latest?.cycle?.cadence.interval == ProbePlanner.idleCeiling)

        harness.clock.advance(by: 780)
        await harness.provider.setViewerObserving(true)
        #expect(await harness.waitUntilProbingRests())
        #expect(harness.transport.sentCount == Int(readings))

        harness.clock.advance(by: 120)
        #expect(await harness.waitForReading(sequence: readings + 1))

        #expect(harness.latest?.cycle?.cadence.nature == .base)
    }

    @Test("cancelar enquanto a espera repousa sem prazo encerra o provedor e termina o fluxo de estados")
    func cancellingWhileWaitingWithoutADeadlineEndsTheProvider() async throws {
        let harness = ProviderHarness(responses: [CannedResponse.rejected()])
        #expect(await harness.waitForState { $0.lastAttempt == .failed(.credentialRejected) })
        #expect(await harness.waitUntilProbingRests())
        #expect(harness.clock.awaitedDeadlines == [.distantFuture])

        harness.cancelRun()

        #expect(await harness.waitUntilStatesFinish())
    }

    @Test("janela limitante ausente é publicada como indisponível, nunca deduzida")
    func absentFieldsArePublishedAsUnavailable() async throws {
        var fixture = UnifiedRateLimitHeaderFixture.complete
        fixture.representativeClaim = nil
        fixture.sevenDayReset = nil

        let harness = ProviderHarness(responses: [CannedResponse.reading(fixture)])
        #expect(await harness.waitForReading(sequence: 1))

        let state = try #require(harness.latest)
        #expect(state.snapshot?.bindingWindow == nil)
        #expect(state.unavailableFields.contains(.bindingWindow))
        #expect(state.unavailableFields.contains(.resetAt(.sevenDay)))
        #expect(!state.unavailableFields.contains(.utilization(.fiveHour)))
    }

    @Test("nenhuma sonda enquanto a máquina dorme; ao acordar volta ao ritmo base")
    func suspensionStopsProbingAndWakeResumesIt() async throws {
        let harness = ProviderHarness(responses: [
            CannedResponse.reading(),
            CannedResponse.reading(),
            CannedResponse.reading()
        ])
        #expect(await harness.waitForReading(sequence: 1))

        harness.power.send(.willSleep)
        #expect(await harness.waitUntilProbingIsSuspended())

        harness.clock.advance(by: 7_200)
        #expect(await harness.waitUntilProbingRests())
        #expect(harness.transport.sentCount == 1)

        let publishedBeforeWake = harness.published.count
        harness.power.send(.didWake)
        #expect(await harness.waitForReading(sequence: 2))

        let afterWake = harness.published.dropFirst(publishedBeforeWake)
        #expect(afterWake.contains { $0.cycle?.cadence.nature == .base })
    }
}
