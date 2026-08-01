import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

private enum Fixture {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)
    static let locale = Locale(identifier: "pt_BR")
    static let timeZone = TimeZone(identifier: "America/Sao_Paulo")!

    static func utilization(_ percent: String?) -> Utilization? {
        guard let percent, let value = Decimal(string: percent) else { return nil }
        return Utilization(originPercent: value)
    }

    static func snapshot(
        fiveHour: String?,
        sevenDay: String?,
        binding: BindingWindow? = nil,
        fiveHourReset: Date? = nil,
        sevenDayReset: Date? = nil,
        source: QuotaSource = .primaryProbe
    ) -> QuotaSnapshot {
        QuotaSnapshot(
            fiveHour: WindowReading(utilization: utilization(fiveHour), resetsAt: fiveHourReset, status: .allowed),
            sevenDay: WindowReading(utilization: utilization(sevenDay), resetsAt: sevenDayReset, status: .allowed),
            overallStatus: .allowed,
            nextResetAt: nil,
            bindingWindow: binding,
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: 1,
            readAt: readAt,
            source: source
        )!
    }

    static func state(
        snapshot: QuotaSnapshot?,
        credentialPresent: Bool = true,
        claudeCodeMissing: Bool = false,
        lastAttempt: AttemptOutcome = .succeeded(at: Fixture.readAt),
        cadenceSeconds: Int = 180,
        nature: ScheduledNature = .base,
        maxIdleSeconds: Int = 180,
        source: QuotaSource = .primaryProbe
    ) -> QuotaState {
        QuotaState(
            credentialPresent: credentialPresent,
            claudeCodeMissing: claudeCodeMissing,
            snapshot: snapshot,
            lastAttempt: lastAttempt,
            cycle: TestCycle.scheduled(.seconds(cadenceSeconds), nature: nature),
            maxIdleCadenceSinceReading: .seconds(maxIdleSeconds),
            source: source
        )
    }

    static func panel(
        _ state: QuotaState?,
        afterSeconds seconds: TimeInterval = 180,
        previouslySeenSource: QuotaSource? = nil
    ) -> PanelContent {
        var latch = StaleLatch()
        var deferral = DeferralLatch()
        let now = readAt.addingTimeInterval(seconds)
        let indicator = state.map { IndicatorStateResolver.resolve(state: $0, latch: &latch, now: now) }
            ?? .notConfigured
        return PanelContentBuilder.build(
            state: state,
            indicator: indicator,
            at: now,
            deferralLatch: &deferral,
            previouslySeenSource: previouslySeenSource,
            locale: locale,
            timeZone: timeZone
        )
    }
}

@Suite("Painel")
struct PanelContentTests {
    @Test("QB-APP-001 AC-18: o painel detalha as duas janelas, nomeadas por extenso, com reset e idade")
    func detailsBothWindows() {
        let reset = Fixture.readAt.addingTimeInterval(3_600)
        let content = Fixture.panel(
            Fixture.state(snapshot: Fixture.snapshot(
                fiveHour: "78", sevenDay: "41", binding: .window(.fiveHour), fiveHourReset: reset
            ))
        )

        #expect(content.fiveHour.name == "Janela de cinco horas")
        #expect(content.sevenDay.name == "Janela semanal")
        #expect(content.fiveHour.utilization == "78%")
        #expect(content.sevenDay.utilization == "41%")
        #expect(content.fiveHour.reset != nil)
        #expect(content.situation.contains("há 3 minutos"))
    }

    @Test("QB-APP-001 AC-19: o painel declara qual janela está na barra e que a origem a informou")
    func declaresSelectionFromOrigin() throws {
        let content = Fixture.panel(
            Fixture.state(snapshot: Fixture.snapshot(fiveHour: "20", sevenDay: "92", binding: .window(.sevenDay)))
        )

        let selection = try #require(content.selection)
        #expect(selection.contains("Janela semanal"))
        #expect(selection.contains("origem"))
    }

    @Test("QB-APP-001 AC-31: quando o app escolhe, o painel declara que a escolha foi dele e por quê")
    func declaresAppChoice() throws {
        let content = Fixture.panel(
            Fixture.state(snapshot: Fixture.snapshot(fiveHour: "31", sevenDay: "67", binding: nil))
        )

        let selection = try #require(content.selection)
        #expect(selection.contains("escolhida pelo QuotaBar"))
        #expect(selection.contains("não informou"))
    }

    @Test("QB-APP-001 AC-20: a ação de encerrar está presente em todos os seis estados")
    func quitIsAlwaysPresent() {
        let value = Fixture.snapshot(fiveHour: "50", sevenDay: nil, binding: .window(.fiveHour))
        let states: [QuotaState] = [
            Fixture.state(snapshot: nil, credentialPresent: false, lastAttempt: .inProgress),
            Fixture.state(snapshot: nil, lastAttempt: .inProgress),
            Fixture.state(snapshot: nil, lastAttempt: .failed(.communicationFailure)),
            Fixture.state(snapshot: value),
            Fixture.state(snapshot: Fixture.snapshot(fiveHour: "100", sevenDay: nil, binding: .window(.fiveHour)))
        ]

        for state in states {
            #expect(!Fixture.panel(state).quitTitle.isEmpty)
        }
        #expect(!Fixture.panel(Fixture.state(snapshot: value), afterSeconds: 11 * 60).quitTitle.isEmpty)
    }

    @Test("QB-APP-001 AC-46: nos estados sem valor o painel abre e declara a ausência, sem zero nem traço")
    func panelWorksWithoutValue() {
        let notConfigured = Fixture.panel(
            Fixture.state(snapshot: nil, credentialPresent: false, lastAttempt: .inProgress)
        )
        let loading = Fixture.panel(Fixture.state(snapshot: nil, lastAttempt: .inProgress))

        for content in [notConfigured, loading] {
            #expect(content.fiveHour.utilization == nil)
            #expect(content.sevenDay.utilization == nil)
            #expect(!content.fiveHour.absences.isEmpty)
            #expect(!content.sevenDay.absences.isEmpty)
            #expect(!content.quitTitle.isEmpty)
            #expect(content.selection == nil)
            #expect(!content.situation.contains("0%"))
            #expect(!content.situation.contains("—"))
        }
        #expect(notConfigured.situation == "Credencial não configurada.")
        #expect(loading.situation == "Primeira leitura em andamento.")
    }

    @Test("QB-APP-001 AC-42: reset não fornecido é declarado ausente, nunca preenchido")
    func missingResetIsDeclared() {
        let content = Fixture.panel(
            Fixture.state(snapshot: Fixture.snapshot(
                fiveHour: "78", sevenDay: "41", binding: .window(.fiveHour),
                fiveHourReset: Fixture.readAt.addingTimeInterval(3_600)
            ))
        )

        #expect(content.sevenDay.reset == nil)
        #expect(content.sevenDay.absences.contains { $0.contains("reset") })
        #expect(content.fiveHour.reset != nil)
    }

    @Test("QB-APP-001 AC-47 e QB-APP-001 AC-43: os sete motivos de falha têm textos distintos entre si")
    func failureReasonsHaveDistinctTexts() {
        let texts = FailureReason.allCases.map { PanelText.reason($0) }

        #expect(Set(texts).count == 7)
        #expect(PanelText.reason(.credentialExpired).contains("expirou"))
        #expect(PanelText.reason(.blockedByPolicy).contains("bloqueou"))
        #expect(PanelText.reason(.blockedByPolicy).contains("Não é defeito do token nem da conta"))
    }

    @Test("QB-APP-001 AC-49: Claude Code não encontrado tem motivo próprio e manda instalá-lo, sem falar em credencial")
    func claudeCodeNotFoundHasItsOwnReason() {
        let content = Fixture.panel(
            Fixture.state(snapshot: nil, claudeCodeMissing: true, lastAttempt: .failed(.claudeCodeNotFound))
        )
        let text = PanelText.reason(.claudeCodeNotFound)

        #expect(content.situation == text)
        #expect(text.contains("Claude Code"))
        #expect(text.contains("Instale"))
        #expect(!text.lowercased().contains("credencial"))
        #expect(!text.lowercased().contains("token"))
    }

    @Test("QB-APP-001 AC-49: com a credencial configurada, só a pendência do Claude Code é declarada")
    func claudeCodePendencyDoesNotDragTheCredentialAlong() {
        let content = Fixture.panel(
            Fixture.state(snapshot: nil, claudeCodeMissing: true, lastAttempt: .failed(.claudeCodeNotFound))
        )

        #expect(content.pendencies == [PanelText.claudeCodePending])
        #expect(content.configureCredentialTitle == nil)
        #expect(content.actionTitles == [PanelText.quit])

        for line in content.pendencies {
            #expect(!line.lowercased().contains("credencial"))
            #expect(!line.lowercased().contains("token"))
        }
    }

    @Test("QB-APP-001 AC-50: com pendência de credencial o painel oferece configurar, e só ela além de encerrar")
    func configureActionExistsWhenCredentialIsPending() {
        let pending = Fixture.panel(
            Fixture.state(snapshot: nil, credentialPresent: false, lastAttempt: .inProgress)
        )

        #expect(pending.configureCredentialTitle == PanelText.configureCredential)
        #expect(pending.actionTitles == [PanelText.configureCredential, PanelText.quit])
        #expect(pending.actionTitles.count == 2)
    }

    @Test("QB-APP-001 AC-50: sem pendência de credencial a única ação é encerrar")
    func configureActionIsAbsentWithoutPendency() {
        let configured = Fixture.panel(
            Fixture.state(snapshot: Fixture.snapshot(fiveHour: "42", sevenDay: nil, binding: .window(.fiveHour)))
        )

        #expect(configured.configureCredentialTitle == nil)
        #expect(configured.actionTitles == [PanelText.quit])
    }

    @Test("QB-APP-001 AC-51: as duas pendências são declaradas na mesma abertura")
    func bothPendenciesAreDeclaredAtOnce() {
        let state = Fixture.state(
            snapshot: nil,
            credentialPresent: false,
            claudeCodeMissing: true,
            lastAttempt: .failed(.claudeCodeNotFound)
        )
        var latch = StaleLatch()
        let indicator = IndicatorStateResolver.resolve(state: state, latch: &latch, now: Fixture.readAt)
        let content = Fixture.panel(state)

        #expect(indicator == .notConfigured)
        #expect(content.pendencies.count == 2)
        #expect(content.pendencies.contains(PanelText.credentialPending))
        #expect(content.pendencies.contains(PanelText.claudeCodePending))
        #expect(content.configureCredentialTitle == PanelText.configureCredential)
    }

    @Test("QB-APP-001 AC-51: resolvida uma pendência, a outra continua declarada sozinha")
    func eachPendencyIsDeclaredOnItsOwn() {
        let onlyClaudeCode = Fixture.panel(
            Fixture.state(
                snapshot: nil,
                credentialPresent: true,
                claudeCodeMissing: true,
                lastAttempt: .failed(.claudeCodeNotFound)
            )
        )
        let onlyCredential = Fixture.panel(
            Fixture.state(snapshot: nil, credentialPresent: false, lastAttempt: .inProgress)
        )
        let none = Fixture.panel(
            Fixture.state(snapshot: Fixture.snapshot(fiveHour: "42", sevenDay: nil, binding: .window(.fiveHour)))
        )

        #expect(onlyClaudeCode.pendencies == [PanelText.claudeCodePending])
        #expect(onlyClaudeCode.configureCredentialTitle == nil)
        #expect(onlyCredential.pendencies == [PanelText.credentialPending])
        #expect(none.pendencies.isEmpty)
    }

    @Test("QB-APP-001 AC-43: bloqueio por política aparece na situação e nenhum percentual antigo é exibido")
    func blockedByPolicyShowsOwnReason() {
        let content = Fixture.panel(
            Fixture.state(snapshot: nil, lastAttempt: .failed(.blockedByPolicy))
        )

        #expect(content.situation == PanelText.reason(.blockedByPolicy))
        #expect(content.fiveHour.utilization == nil)
        #expect(content.sevenDay.utilization == nil)
    }

    @Test("QB-APP-001 AC-35 e QB-APP-001 AC-37: a linha de cadência traz intervalo e natureza")
    func cadenceLineCarriesIntervalAndNature() {
        let idle = Fixture.panel(
            Fixture.state(
                snapshot: Fixture.snapshot(fiveHour: "30", sevenDay: nil, binding: .window(.fiveHour)),
                cadenceSeconds: 900, nature: .idle, maxIdleSeconds: 900
            ),
            afterSeconds: 12 * 60
        )
        let base = Fixture.panel(
            Fixture.state(snapshot: Fixture.snapshot(fiveHour: "30", sevenDay: nil, binding: .window(.fiveHour)))
        )
        let widened = Fixture.panel(
            Fixture.state(
                snapshot: Fixture.snapshot(fiveHour: "30", sevenDay: nil, binding: .window(.fiveHour)),
                cadenceSeconds: 1_800, nature: .widenedByFailure
            )
        )

        #expect(idle.cadenceLine == "Atualizando a cada 15 minutos — reduzido por ociosidade.")
        #expect(base.cadenceLine == "Atualizando a cada 3 minutos — ritmo base.")
        #expect(widened.cadenceLine == "Atualizando a cada 30 minutos — ampliado por falha.")
    }

    @Test("QB-APP-001 AC-36: a cadência voltar ao ritmo base não muda o estado do indicador")
    func returningToBaseCadenceDoesNotChangeState() {
        let snapshot = Fixture.snapshot(fiveHour: "30", sevenDay: nil, binding: .window(.fiveHour))
        let now = Fixture.readAt.addingTimeInterval(28 * 60)
        var latch = StaleLatch()

        let underIdle = IndicatorStateResolver.resolve(
            state: Fixture.state(snapshot: snapshot, cadenceSeconds: 900, nature: .idle, maxIdleSeconds: 900),
            latch: &latch,
            now: now
        )
        let afterOpeningPanel = IndicatorStateResolver.resolve(
            state: Fixture.state(snapshot: snapshot, cadenceSeconds: 180, nature: .base, maxIdleSeconds: 900),
            latch: &latch,
            now: now
        )

        #expect(underIdle == afterOpeningPanel)
        if case .ready = afterOpeningPanel {} else {
            Issue.record("indicador deixou de estar ready ao abrir o painel: \(afterOpeningPanel)")
        }
    }

    @Test("QB-APP-001 AC-40: a mudança de fonte é anunciada e a contingência lista o que não entrega")
    func sourceChangeIsAnnounced() {
        let content = Fixture.panel(
            Fixture.state(
                snapshot: Fixture.snapshot(
                    fiveHour: "22", sevenDay: "70", binding: nil, source: .contingencyStatusLine
                ),
                source: .contingencyStatusLine
            ),
            previouslySeenSource: .primaryProbe
        )

        #expect(content.sourceChangeNotice != nil)
        #expect(content.source == PanelText.sourceName(.contingencyStatusLine))
        #expect(content.contingencyLosses.count == 3)
        #expect(content.contingencyLosses.contains { $0.contains("janela limita") })
    }

    @Test("QB-APP-001 AC-40: sem mudança de fonte não há aviso")
    func noNoticeWithoutSourceChange() {
        let content = Fixture.panel(
            Fixture.state(snapshot: Fixture.snapshot(fiveHour: "30", sevenDay: nil, binding: .window(.fiveHour))),
            previouslySeenSource: .primaryProbe
        )

        #expect(content.sourceChangeNotice == nil)
        #expect(content.contingencyLosses.isEmpty)
    }

    @Test("QB-APP-001 AC-41: em contingência a seleção usa a regra de contorno e declara isso")
    func contingencyUsesFallbackSelection() throws {
        let content = Fixture.panel(
            Fixture.state(
                snapshot: Fixture.snapshot(
                    fiveHour: "22", sevenDay: "70", binding: nil, source: .contingencyStatusLine
                ),
                source: .contingencyStatusLine
            )
        )

        let selection = try #require(content.selection)
        #expect(selection.contains("Janela semanal"))
        #expect(selection.contains("não informou"))
    }

    @Test("QB-APP-001 AC-48: em contingência sem credencial o painel declara que não há retorno à fonte primária")
    func contingencyWithoutCredentialDeclaresNoReturn() {
        let content = Fixture.panel(
            Fixture.state(
                snapshot: Fixture.snapshot(
                    fiveHour: "33", sevenDay: nil, binding: nil, source: .contingencyStatusLine
                ),
                credentialPresent: false,
                source: .contingencyStatusLine
            )
        )

        #expect(content.credentialNotice == PanelText.credentialAbsentInContingency)
        #expect(content.fiveHour.utilization == "33%")
    }

    @Test("QB-APP-001 AC-23: idade de leitura no futuro nunca é exibida como tempo negativo")
    func futureReadingShowsNoNegativeAge() {
        let content = Fixture.panel(
            Fixture.state(snapshot: Fixture.snapshot(fiveHour: "30", sevenDay: nil, binding: .window(.fiveHour))),
            afterSeconds: -3_600
        )

        #expect(content.situation.contains("há menos de um minuto"))
        #expect(!content.situation.contains("-"))
    }
}
