import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

private enum Card {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)

    static func content(
        fiveHour: String?,
        sevenDay: String? = nil,
        fiveHourReset: Date? = nil,
        nature: ScheduledNature = .base,
        cadenceSeconds: Int = 180,
        afterSeconds: TimeInterval = 60
    ) -> PanelContent {
        let snapshot = QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: fiveHour.map { Utilization(originPercent: Decimal(string: $0)!)! },
                resetsAt: fiveHourReset,
                status: .allowed
            ),
            sevenDay: WindowReading(
                utilization: sevenDay.map { Utilization(originPercent: Decimal(string: $0)!)! },
                resetsAt: nil,
                status: .allowed
            ),
            overallStatus: .allowed,
            nextResetAt: nil,
            bindingWindow: .window(.fiveHour),
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: 1,
            readAt: readAt,
            source: .primaryProbe
        )!
        let state = QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .succeeded(at: readAt),
            cycle: TestCycle.scheduled(.seconds(cadenceSeconds), nature: nature),
            maxIdleCadenceSinceReading: .seconds(cadenceSeconds),
            source: .primaryProbe
        )

        var latch = StaleLatch()
        var deferral = DeferralLatch()
        let now = readAt.addingTimeInterval(afterSeconds)
        let indicator = IndicatorStateResolver.resolve(state: state, latch: &latch, now: now)
        return PanelContentBuilder.build(
            state: state, indicator: indicator, at: now, deferralLatch: &deferral
        )
    }
}

@Suite("Cartões do painel")
struct PanelCardTests {
    @Test(
        "QB-APP-002 AC-14: o cartão acende os segmentos do medidor conforme o percentual",
        arguments: [
            (percent: "0", lit: 0),
            (percent: "0.1", lit: 1),
            (percent: "5", lit: 1),
            (percent: "5.1", lit: 2),
            (percent: "50", lit: 10),
            (percent: "78.9", lit: 16),
            (percent: "100", lit: 20)
        ]
    )
    func meterInTheCard(percent: String, lit: Int) {
        #expect(Card.content(fiveHour: percent).fiveHour.litSegments == lit)
    }

    @Test("QB-APP-002 AC-14: em 78,9% o cartão mostra 16 segmentos e o número 78%")
    func meterRoundsUpWhileNumberTruncates() {
        let card = Card.content(fiveHour: "78.9").fiveHour

        #expect(card.litSegments == 16)
        #expect(card.utilization == "78%")
    }

    @Test("QB-APP-002 AC-14: o caso conhecido de 74,9% mantém medidor em 15 e número em 74%")
    func theKnownIncoherenceAtSeventyFourPointNine() {
        let card = Card.content(fiveHour: "74.9").fiveHour

        #expect(card.litSegments == 15)
        #expect(card.utilization == "74%")
    }

    @Test("QB-APP-002 AC-15: o cartão é tingido pela cor contínua do gradiente")
    func cardIsTintedByTheGradient() {
        #expect(Card.content(fiveHour: "0").fiveHour.tint == Palette.ok)
        #expect(Card.content(fiveHour: "75").fiveHour.tint == Palette.warning)
        #expect(Card.content(fiveHour: "100").fiveHour.tint == Palette.bad)
    }

    @Test("QB-APP-002 AC-15: a cor do cartão não salta nas fronteiras de faixa da barra")
    func cardTintDoesNotJumpAtBandBoundaries() {
        let before = Card.content(fiveHour: "74").fiveHour.tint!
        let after = Card.content(fiveHour: "75").fiveHour.tint!

        let distance = abs(before.red - after.red) + abs(before.green - after.green) + abs(before.blue - after.blue)
        #expect(distance < 0.03)
    }

    @Test("QB-APP-002 AC-16: abaixo de uma hora a contagem traz segundos")
    func countdownBelowOneHourHasSeconds() {
        let card = Card.content(
            fiveHour: "50",
            fiveHourReset: Card.readAt.addingTimeInterval(60 + 50 * 60),
            afterSeconds: 60
        ).fiveHour

        #expect(card.countdown == "50:00")
    }

    @Test("QB-APP-002 AC-16: acima de uma hora a contagem omite segundos")
    func countdownAboveOneHourOmitsSeconds() {
        let card = Card.content(
            fiveHour: "50",
            fiveHourReset: Card.readAt.addingTimeInterval(60 + 90 * 60),
            afterSeconds: 60
        ).fiveHour

        #expect(card.countdown == "1h 30min")
    }

    @Test("QB-APP-002 AC-16: o formato do texto acompanha a política, e não o contrário")
    func countdownTextFollowsThePolicy() {
        #expect(CountdownText.text(remaining: .seconds(3_599), format: .withSeconds) == "59:59")
        #expect(CountdownText.text(remaining: .seconds(3_600), format: .minutesOnly) == "1h 0min")
        #expect(CountdownText.text(remaining: .seconds(90_000), format: .minutesOnly) == "1d 1h")
        #expect(CountdownText.text(remaining: .zero, format: .withSeconds) == "0:00")
        #expect(CountdownText.text(remaining: .seconds(-30), format: .withSeconds) == "0:00")
    }

    @Test("QB-APP-002 AC-13 e QB-APP-001 REQ-19: reset ausente omite a contagem em vez de zerar")
    func absentResetOmitsTheCountdown() {
        let card = Card.content(fiveHour: "50", fiveHourReset: nil).fiveHour

        #expect(card.countdown == nil)
        #expect(card.reset == nil)
        #expect(card.absences.contains { $0.contains("reset") })
    }

    @Test("QB-APP-002 AC-13: sem valor exibível o medidor fica apagado e não vira marcador de ausência")
    func absentValueLeavesTheMeterDark() {
        var latch = StaleLatch()
        var deferral = DeferralLatch()
        let state = QuotaState(
            credentialPresent: false,
            snapshot: nil,
            lastAttempt: .inProgress,
            cycle: nil,
            maxIdleCadenceSinceReading: .seconds(180),
            source: nil
        )
        let indicator = IndicatorStateResolver.resolve(state: state, latch: &latch, now: Card.readAt)
        let content = PanelContentBuilder.build(
            state: state, indicator: indicator, at: Card.readAt, deferralLatch: &deferral
        )

        #expect(content.fiveHour.litSegments == 0)
        #expect(content.fiveHour.tint == nil)
        #expect(content.fiveHour.countdown == nil)
        #expect(content.cadence == nil)
    }

    @Test("QB-APP-002 AC-18: a barra de cadência representa o progresso até a próxima leitura")
    func cadenceBarShowsProgress() {
        let atStart = Card.content(fiveHour: "50", cadenceSeconds: 180, afterSeconds: 0).cadence
        let midway = Card.content(fiveHour: "50", cadenceSeconds: 180, afterSeconds: 90).cadence
        let past = Card.content(fiveHour: "50", cadenceSeconds: 180, afterSeconds: 600).cadence

        #expect(atStart?.progress == 0)
        #expect(abs((midway?.progress ?? 0) - 0.5) < 0.001)
        #expect(past?.progress == 1)
    }

    @Test("QB-APP-002 AC-18: a barra é coerente com o que a linha de cadência declara em texto")
    func cadenceBarAgreesWithTheCadenceLine() {
        let content = Card.content(fiveHour: "50", nature: .idle, cadenceSeconds: 900)

        #expect(content.cadence?.nature == .idle)
        #expect(content.cadenceLine?.contains("reduzido por ociosidade") == true)
        #expect(content.cadenceLine?.contains("15 minutos") == true)
    }

    @Test("QB-APP-002 AC-13: o cartão não acrescenta informação além da exigida")
    func theCardAddsNothingBeyondWhatIsRequired() {
        let content = Card.content(
            fiveHour: "78",
            sevenDay: "41",
            fiveHourReset: Card.readAt.addingTimeInterval(3_600)
        )

        #expect(content.fiveHour.utilization == "78%")
        #expect(content.sevenDay.utilization == "41%")
        #expect(content.fiveHour.reset != nil)
        #expect(content.sevenDay.reset == nil)
        #expect(content.selection != nil)
        #expect(content.cadenceLine != nil)
        #expect(content.source != nil)
        #expect(!content.quitTitle.isEmpty)
    }
}

@MainActor
@Suite("Temporizador da contagem regressiva")
struct CountdownTickerTests {
    @Test("QB-APP-002 AC-17: sem painel aberto o temporizador não corre")
    func tickerDoesNotRunBeforeStarting() async throws {
        let ticker = CountdownTicker()

        #expect(!ticker.isRunning)
        try await Task.sleep(for: .milliseconds(120))
        #expect(ticker.tickCount == 0)
    }

    @Test("QB-APP-002 AC-17: fechar o painel para o temporizador e ele não volta sozinho")
    func stoppingHaltsTheTicker() async throws {
        let ticker = CountdownTicker()
        ticker.start(nextDeadline: Date().addingTimeInterval(600))
        #expect(ticker.isRunning)

        try await Task.sleep(for: .milliseconds(1_200))
        let whileRunning = ticker.tickCount
        #expect(whileRunning > 0)

        ticker.stop()
        #expect(!ticker.isRunning)
        #expect(ticker.currentInterval == nil)

        try await Task.sleep(for: .milliseconds(1_500))
        #expect(ticker.tickCount == whileRunning, "o temporizador continuou depois de parar")
    }

    @Test("QB-APP-002 AC-16: abaixo de uma hora o temporizador escolhe 1 segundo")
    func belowOneHourTicksEverySecond() async throws {
        let ticker = CountdownTicker()
        ticker.start(nextDeadline: Date().addingTimeInterval(50 * 60))

        try await Task.sleep(for: .milliseconds(100))
        #expect(ticker.currentInterval == .seconds(1))
        ticker.stop()
    }

    @Test("QB-APP-002 AC-16: acima de uma hora o temporizador escolhe 60 segundos e não paga 1 Hz")
    func aboveOneHourTicksEveryMinute() async throws {
        let ticker = CountdownTicker()
        ticker.start(nextDeadline: Date().addingTimeInterval(90 * 60))

        try await Task.sleep(for: .milliseconds(100))
        #expect(ticker.currentInterval == .seconds(60))

        try await Task.sleep(for: .milliseconds(1_500))
        #expect(ticker.tickCount == 0, "houve tique a 1 Hz com reset a mais de uma hora")
        ticker.stop()
    }

    @Test("QB-APP-002 AC-17: sem instante de reset não há o que contar, e nada é iniciado")
    func noDeadlineStartsNothing() async throws {
        let ticker = CountdownTicker()
        ticker.start(nextDeadline: nil)

        #expect(!ticker.isRunning)
        try await Task.sleep(for: .milliseconds(120))
        #expect(ticker.tickCount == 0)
    }

    @Test("QB-APP-002 AC-17: reiniciar substitui o temporizador em vez de acumular outro")
    func restartingReplacesTheTicker() async throws {
        let ticker = CountdownTicker()
        ticker.start(nextDeadline: Date().addingTimeInterval(600))
        ticker.start(nextDeadline: Date().addingTimeInterval(600))
        ticker.start(nextDeadline: Date().addingTimeInterval(600))

        try await Task.sleep(for: .milliseconds(1_200))
        #expect(ticker.tickCount <= 2, "mais de um temporizador ficou vivo: \(ticker.tickCount) tiques em 1,2 s")
        ticker.stop()
    }
}
