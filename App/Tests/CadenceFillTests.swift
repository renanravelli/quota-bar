import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

private enum Fill {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)
    static let opened = readAt.addingTimeInterval(60)

    static func state(cadenceSeconds: Int = 180, reset: Date? = nil) -> QuotaState {
        let snapshot = QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: Utilization(originPercent: 50)!,
                resetsAt: reset,
                status: .allowed
            ),
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
            cycle: TestCycle.scheduled(.seconds(cadenceSeconds)),
            maxIdleCadenceSinceReading: .seconds(cadenceSeconds),
            source: .primaryProbe
        )
    }

    static func progress(of state: QuotaState, at now: Date) -> Double? {
        var latch = StaleLatch()
        var deferral = DeferralLatch()
        let indicator = IndicatorStateResolver.resolve(state: state, latch: &latch, now: now)

        return PanelContentBuilder.build(
            state: state, indicator: indicator, at: now, deferralLatch: &deferral
        ).cadenceBar?.progress
    }
}

@Suite("Preenchimento da barra de cadência")
struct CadenceFillTests {
    @Test("QB-APP-002 AC-18: o preenchimento avança sem que haja instante de reset conhecido")
    func fillAdvancesWithoutAKnownReset() throws {
        let state = Fill.state(reset: nil)
        let samples = try stride(from: 0.0, through: 180.0, by: 30.0).map { second in
            try #require(Fill.progress(of: state, at: Fill.readAt.addingTimeInterval(second)))
        }

        #expect(samples == samples.sorted())
        #expect(Set(samples).count == samples.count, "o preenchimento repetiu valores em vez de avançar")
        #expect(samples.first == 0)
        #expect(samples.last == 1, "o preenchimento não chegou a saturar na tela")
    }

    @Test("QB-APP-002 AC-18: o preenchimento não herda a granularidade da contagem regressiva")
    func fillDoesNotInheritTheCountdownGranularity() throws {
        let coarse = CountdownPolicy.refreshInterval(for: .minutesOnly)
        let fill = CadenceFillPolicy.refreshInterval(for: .seconds(180))
        #expect(fill < coarse)

        let state = Fill.state(cadenceSeconds: 180)
        let stepsAtTheCountdownPace = try distinctProgressValues(of: state, sampledEvery: coarse)
        let stepsAtTheFillPace = try distinctProgressValues(of: state, sampledEvery: fill)

        #expect(stepsAtTheCountdownPace == 3, "a granularidade herdada daria três degraus em três minutos")
        #expect(stepsAtTheFillPace == CadenceFillPolicy.stepsPerCadence)
    }

    @Test("QB-APP-002 REQ-18: o preenchimento nunca é amostrado mais rápido que 1 Hz, nem mais lento que 5 s")
    func theFillPaceStaysWithinItsBounds() {
        for seconds in [60, 120, 180, 300, 900, 3_600] {
            let interval = CadenceFillPolicy.refreshInterval(for: .seconds(seconds))
            #expect(interval >= CadenceFillPolicy.fastest)
            #expect(interval <= CadenceFillPolicy.slowest)
        }

        #expect(CadenceFillPolicy.refreshInterval(for: Cadence.floor) == CadenceFillPolicy.fastest)
        #expect(CadenceFillPolicy.refreshInterval(for: .seconds(900)) == CadenceFillPolicy.slowest)
    }

    private func distinctProgressValues(of state: QuotaState, sampledEvery interval: Duration) throws -> Int {
        let cadence = try #require(state.cycle).cadence.interval.seconds
        let samples = stride(from: 0, to: cadence, by: interval.seconds).map { second in
            Fill.progress(of: state, at: Fill.readAt.addingTimeInterval(second))
        }

        return Set(samples.compactMap { $0 }).count
    }
}

@MainActor
@Suite("Temporizador do preenchimento da barra de cadência")
struct CadenceFillTickerTests {
    @Test("QB-APP-002 AC-18: o temporizador corre sem depender de instante de reset conhecido")
    func theTickerRunsWithoutAnyDeadline() async throws {
        let presenter = IndicatorPresenter(
            provider: RecordingQuotaStateProvider(),
            clock: { Fill.opened },
            reduceMotion: { .off }
        )
        presenter.receive(Fill.state(reset: nil))
        #expect(presenter.nearestReset == nil, "a fixture precisa não ter reset para o teste valer")

        let ticker = CadenceFillTicker()
        ticker.start(cadence: presenter.state.cycle?.cadence)

        #expect(ticker.isRunning)
        #expect(ticker.currentInterval == CadenceFillPolicy.refreshInterval(for: .seconds(180)))

        try await Task.sleep(for: .milliseconds(1_800))
        #expect(ticker.tickCount > 0, "o preenchimento congelou por não haver reset conhecido")

        ticker.stop()
    }

    @Test("QB-APP-002 REQ-11: sem cadência não há preenchimento a mover, e nada é iniciado")
    func noCadenceStartsNothing() async throws {
        let ticker = CadenceFillTicker()
        ticker.start(cadence: nil)

        #expect(!ticker.isRunning)
        try await Task.sleep(for: .milliseconds(120))
        #expect(ticker.tickCount == 0)
    }

    @Test("QB-APP-002 REQ-11: fechar o painel para o preenchimento, e ele não volta sozinho")
    func stoppingHaltsTheFillTicker() async throws {
        let ticker = CadenceFillTicker()
        ticker.start(cadence: ScheduledCadence(interval: ScheduledCadence.floor, nature: .base))

        try await Task.sleep(for: .milliseconds(1_200))
        let whileRunning = ticker.tickCount
        #expect(whileRunning > 0)

        ticker.stop()
        #expect(!ticker.isRunning)
        #expect(ticker.currentInterval == nil)

        try await Task.sleep(for: .milliseconds(1_500))
        #expect(ticker.tickCount == whileRunning, "o temporizador continuou depois de parar")
    }

    @Test("QB-APP-002 REQ-11: reiniciar substitui o temporizador em vez de acumular outro")
    func restartingReplacesTheFillTicker() async throws {
        let ticker = CadenceFillTicker()
        let cadence = ScheduledCadence(interval: ScheduledCadence.floor, nature: .base)
        ticker.start(cadence: cadence)
        ticker.start(cadence: cadence)
        ticker.start(cadence: cadence)

        try await Task.sleep(for: .milliseconds(1_200))
        #expect(ticker.tickCount <= 2, "mais de um temporizador ficou vivo: \(ticker.tickCount) tiques em 1,2 s")
        ticker.stop()
    }

    @Test("QB-APP-002 AC-20: o instante de renderização é o corrente, sem depender de marcação de temporizador")
    func theRenderInstantDoesNotDependOnAnyTickerHavingMarkedIt() {
        let launch = Fill.readAt
        let opening = Fill.readAt.addingTimeInterval(3 * 3_600)
        let hand = SettableClock(launch)
        let render = PanelRenderClock(clock: hand.read)

        hand.set(opening)

        #expect(render.instant == opening, "a renderização partiu do instante em que o aplicativo subiu")
    }

    @Test("QB-APP-002 AC-18: o instante de renderização avança no passo do preenchimento, não no da contagem")
    func theFillPaceDrivesTheRenderInstantWhileTheCountdownIsCoarse() async throws {
        let render = PanelRenderClock()
        let countdown = CountdownTicker(requestRender: render.mark)
        let fill = CadenceFillTicker(requestRender: render.mark)

        countdown.start(nextDeadline: Date().addingTimeInterval(7_200))
        fill.start(cadence: ScheduledCadence(interval: ScheduledCadence.floor, nature: .base))

        try await Task.sleep(for: .milliseconds(2_600))
        #expect(countdown.currentInterval == CountdownPolicy.refreshInterval(for: .minutesOnly))
        countdown.stop()
        fill.stop()

        #expect(countdown.tickCount == 0, "a contagem grossa não deveria ter disparado nesta janela")
        #expect(fill.tickCount >= 2, "o preenchimento herdou a granularidade da contagem regressiva")
    }
}
