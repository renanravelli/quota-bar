import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

private enum Fixture {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)

    static func state(
        percent: String,
        window: QuotaWindow = .fiveHour,
        source: QuotaSource = .primaryProbe
    ) -> QuotaState {
        let utilization = Utilization(originPercent: Decimal(string: percent)!)!
        let reading = WindowReading(utilization: utilization, resetsAt: nil, status: .allowed)
        let empty = WindowReading(utilization: nil, resetsAt: nil, status: .allowed)
        let snapshot = QuotaSnapshot(
            fiveHour: window == .fiveHour ? reading : empty,
            sevenDay: window == .sevenDay ? reading : empty,
            overallStatus: .allowed,
            nextResetAt: nil,
            bindingWindow: .window(window),
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: 1,
            readAt: readAt,
            source: source
        )!

        return QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .succeeded(at: readAt),
            cycle: TestCycle.scheduled(),
            maxIdleCadenceSinceReading: .seconds(180),
            source: source
        )
    }

    @MainActor
    static func presenter(
        reduceMotion: ReduceMotionPreference = .off,
        episodeDuration: Duration = .milliseconds(200)
    ) -> IndicatorPresenter {
        IndicatorPresenter(
            provider: RecordingQuotaStateProvider(),
            clock: { readAt.addingTimeInterval(60) },
            reduceMotion: { reduceMotion },
            episodeDuration: episodeDuration
        )
    }
}

@MainActor
@Suite("Episódio no indicador")
struct EpisodeLifecycleTests {
    @Test("o apresentador entra em episódio ao cruzar faixa")
    func bandCrossingStartsAnEpisode() async throws {
        let presenter = Fixture.presenter()
        presenter.receive(Fixture.state(percent: "50"))
        try await Task.sleep(for: .milliseconds(400))
        #expect(!presenter.isInEpisode)

        presenter.receive(Fixture.state(percent: "80"))

        #expect(presenter.isInEpisode)
        #expect(presenter.symbolAppearance.shape == .attention)
    }

    @Test("o apresentador entra em episódio ao mudar de estado")
    func stateChangeStartsAnEpisode() {
        let presenter = Fixture.presenter()

        presenter.receive(Fixture.state(percent: "50"))

        #expect(presenter.isInEpisode)
    }

    @Test("o apresentador entra em episódio ao trocar a janela exibida")
    func windowChangeStartsAnEpisode() async throws {
        let presenter = Fixture.presenter()
        presenter.receive(Fixture.state(percent: "50", window: .fiveHour))
        try await Task.sleep(for: .milliseconds(400))
        #expect(!presenter.isInEpisode)

        presenter.receive(Fixture.state(percent: "50", window: .sevenDay))

        #expect(presenter.isInEpisode)
    }

    @Test("o apresentador entra em episódio ao mudar o modo de fonte")
    func sourceChangeStartsAnEpisode() async throws {
        let presenter = Fixture.presenter()
        presenter.receive(Fixture.state(percent: "50", source: .primaryProbe))
        try await Task.sleep(for: .milliseconds(400))

        presenter.receive(Fixture.state(percent: "50", source: .contingencyStatusLine))

        #expect(presenter.isInEpisode)
    }

    @Test("o episódio termina sozinho, sem depender de novo evento")
    func episodeEndsOnItsOwn() async throws {
        let presenter = Fixture.presenter()
        presenter.receive(Fixture.state(percent: "50"))
        presenter.receive(Fixture.state(percent: "80"))
        #expect(presenter.isInEpisode)

        try await Task.sleep(for: .milliseconds(400))

        #expect(!presenter.isInEpisode)
    }

    @Test("durante o episódio o símbolo ganha cor e devolve ao template no fim")
    func episodeColoursAndReturnsToTemplate() async throws {
        let presenter = Fixture.presenter()
        presenter.receive(Fixture.state(percent: "50"))
        presenter.receive(Fixture.state(percent: "80"))

        guard case .colored = presenter.symbolAppearance.tint else {
            Issue.record("o episódio deveria colorir o símbolo")
            return
        }

        try await Task.sleep(for: .milliseconds(400))

        #expect(presenter.symbolAppearance.tint == .template)
    }

    @Test("um segundo evento substitui o episódio e reinicia a duração a partir dele")
    func secondEventReplacesInsteadOfQueueing() async throws {
        let presenter = Fixture.presenter(episodeDuration: .milliseconds(300))
        presenter.receive(Fixture.state(percent: "50"))
        presenter.receive(Fixture.state(percent: "80"))

        try await Task.sleep(for: .milliseconds(200))
        presenter.receive(Fixture.state(percent: "95"))
        #expect(presenter.isInEpisode)

        try await Task.sleep(for: .milliseconds(200))
        #expect(presenter.isInEpisode, "o episódio terminou no prazo do primeiro evento, não do segundo")

        try await Task.sleep(for: .milliseconds(250))
        #expect(!presenter.isInEpisode, "o episódio não terminou após a duração do segundo evento")
    }

    @Test("nenhum episódio fica pendente depois do último terminar")
    func noEpisodeRemainsPending() async throws {
        let presenter = Fixture.presenter()
        presenter.receive(Fixture.state(percent: "50"))
        presenter.receive(Fixture.state(percent: "80"))
        presenter.receive(Fixture.state(percent: "95"))

        try await Task.sleep(for: .milliseconds(400))
        #expect(!presenter.isInEpisode)

        try await Task.sleep(for: .milliseconds(300))
        #expect(!presenter.isInEpisode, "um episódio enfileirado ressurgiu depois do término")
    }

    @Test("estado idêntico não dispara episódio")
    func identicalStateDoesNotTrigger() async throws {
        let presenter = Fixture.presenter()
        presenter.receive(Fixture.state(percent: "50"))
        try await Task.sleep(for: .milliseconds(400))

        presenter.receive(Fixture.state(percent: "50"))

        #expect(!presenter.isInEpisode)
    }

    @Test("o apresentador não entra em episódio com variação de percentual dentro da mesma faixa")
    func percentChangeWithinBandDoesNotTrigger() async throws {
        let presenter = Fixture.presenter()
        presenter.receive(Fixture.state(percent: "50"))
        try await Task.sleep(for: .milliseconds(400))

        presenter.receive(Fixture.state(percent: "60"))

        #expect(!presenter.isInEpisode)
    }

    @Test("sem evento algum, a imagem do item não é reconstruída")
    func noRebuildWithoutEvents() async throws {
        let presenter = Fixture.presenter()
        presenter.receive(Fixture.state(percent: "50"))
        try await Task.sleep(for: .milliseconds(400))

        let baseline = presenter.symbolRebuildCount

        for _ in 0..<20 {
            presenter.receive(Fixture.state(percent: "50"))
        }
        try await Task.sleep(for: .milliseconds(300))

        #expect(presenter.symbolRebuildCount == baseline)
    }

    @Test("um episódio custa exatamente duas reconstruções, entrada e volta")
    func anEpisodeCostsTwoRebuilds() async throws {
        let presenter = Fixture.presenter()
        presenter.receive(Fixture.state(percent: "50"))
        try await Task.sleep(for: .milliseconds(400))

        let baseline = presenter.symbolRebuildCount
        presenter.receive(Fixture.state(percent: "80"))
        try await Task.sleep(for: .milliseconds(400))

        #expect(presenter.symbolRebuildCount - baseline == 2)
    }

    @Test("com Reduzir movimento não há episódio, e o estado final continua correto")
    func reduceMotionSuppressesTheEpisode() async throws {
        let presenter = Fixture.presenter(reduceMotion: .on)
        presenter.receive(Fixture.state(percent: "50"))
        presenter.receive(Fixture.state(percent: "80"))

        #expect(!presenter.isInEpisode)
        #expect(presenter.symbolAppearance.tint == .template)
        #expect(presenter.symbolAppearance.shape == .attention)
        #expect(presenter.indicatorText == "5h 80%")
    }

    @Test("preferência indeterminada também não anima")
    func undeterminedPreferenceSuppressesTheEpisode() {
        let presenter = Fixture.presenter(reduceMotion: .undetermined)
        presenter.receive(Fixture.state(percent: "50"))
        presenter.receive(Fixture.state(percent: "80"))

        #expect(!presenter.isInEpisode)
    }
}
