import Foundation
import QuotaBarCore
import Testing

@testable import QuotaBarTransport

private actor ProgressLog {
    private(set) var stages: [AssistedSetupProgress] = []

    func record(_ stage: AssistedSetupProgress) {
        stages.append(stage)
    }

    nonisolated var sink: @Sendable (AssistedSetupProgress) -> Void {
        { stage in Task { await self.record(stage) } }
    }
}

@Suite("Condução assistida da obtenção da credencial", .timeLimit(.minutes(1)))
struct SetupTokenCredentialAcquirerTests {
    @Test("o token casado no fluxo do filho vira a credencial obtida")
    func aMatchedTokenBecomesTheObtainedCredential() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { spawner.spawnCount == 1 }
        spawner.session.emit(Assisted.frame(around: assistedCanary))

        let token = await outcome.acquiredToken
        #expect(token?.withValue { $0 } == assistedCanary)
        #expect(spawner.session.terminationCount >= 1)
    }

    @Test("sem o Claude Code encontrado, nenhum processo chega a ser lançado")
    func withoutClaudeCodeNoProcessIsLaunched() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(discovery: .notFound, spawner: spawner)

        let outcome = await acquirer.acquire { _ in }

        #expect(outcome.unavailability == .claudeCodeNotFound)
        #expect(spawner.spawnCount == 0)
    }

    @Test("condução que não pode ser lançada tem causa própria, distinta do silêncio")
    func aConductionThatCannotBeLaunchedHasItsOwnCause() async {
        let acquirer = Assisted.acquirer(spawner: FakePseudoTerminal(failingWith: PseudoTerminalFailure.cannotLaunch))

        let outcome = await acquirer.acquire { _ in }

        #expect(outcome.unavailability == .launchFailed)
        #expect(outcome.unavailability != .silentBeforeAnySign)
    }

    @Test("fluxo que termina sem token e com status zero não produz credencial")
    func aStreamThatEndsWithoutATokenProducesNoCredential() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { spawner.spawnCount == 1 }
        spawner.session.emit("nada de token aqui\r\n")
        spawner.session.endStream(status: 0)

        #expect(await outcome.unavailability == .endedWithoutCredential)
    }

    @Test("saída não nula antes do casamento é lida como recusa por política")
    func aNonZeroExitBeforeMatchingIsReadAsAPolicyRefusal() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { spawner.spawnCount == 1 }
        spawner.session.emit("creates a long-lived token, which this policy does not permit.\r\n")
        spawner.session.endStream(status: 1)

        #expect(await outcome.unavailability == .refusedByPolicy)
    }

    @Test("fluxo que esgota o limite de varredura não produz credencial")
    func anExhaustedScanProducesNoCredential() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { spawner.spawnCount == 1 }
        for _ in 0...(SetupTokenScanner.scanLimit / (1 << 16)) {
            spawner.session.emit([UInt8](repeating: 0x78, count: 1 << 16))
        }

        #expect(await outcome.unavailability == .endedWithoutCredential)
    }

    @Test("vinte segundos sem nenhum sinal de vida encerram a condução com desfecho próprio")
    func twentySilentSecondsEndTheConduction() async {
        let clock = ManualClock()
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner, clock: clock)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { clock.sleeperCount == 1 }
        clock.advance(by: .seconds(20))

        #expect(await outcome.unavailability == .silentBeforeAnySign)
        #expect(spawner.session.terminationCount >= 1)
    }

    @Test("três minutos depois do primeiro sinal encerram a espera pela aprovação, e nem um segundo antes")
    func threeMinutesAfterTheFirstSignEndTheWait() async {
        let clock = ManualClock()
        let spawner = FakePseudoTerminal()
        let log = ProgressLog()
        let acquirer = Assisted.acquirer(spawner: spawner, clock: clock)

        async let outcome = acquirer.acquire(onProgress: log.sink)
        await Assisted.settle { clock.sleeperCount == 1 }
        spawner.session.emit("\u{1B}[2Jabrindo o navegador\r\n")
        await Assisted.settle { await log.stages.contains(.waitingForApproval) }

        clock.advance(by: .seconds(179))
        await Assisted.settle { clock.sleeperCount == 1 }
        #expect(spawner.session.terminationCount == 0)

        clock.advance(by: .seconds(1))
        #expect(await outcome.unavailability == .approvalTimedOut)
    }

    @Test("um salto único do relógio alcança o prazo, porque o prazo é comparação e não temporizador")
    func aSingleClockJumpReachesTheDeadline() async {
        let clock = ManualClock()
        let spawner = FakePseudoTerminal()
        let log = ProgressLog()
        let acquirer = Assisted.acquirer(spawner: spawner, clock: clock)

        async let outcome = acquirer.acquire(onProgress: log.sink)
        await Assisted.settle { clock.sleeperCount == 1 }
        spawner.session.emit("primeiro sinal\r\n")
        await Assisted.settle { await log.stages.contains(.waitingForApproval) }

        clock.advance(by: .seconds(3_600))

        #expect(await outcome.unavailability == .approvalTimedOut)
    }

    @Test("antes de decorrida a duração, a espera não vence e a credencial ainda pode chegar")
    func theWaitDoesNotExpireBeforeItsDuration() async {
        let clock = ManualClock()
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner, clock: clock)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { clock.sleeperCount == 1 }

        clock.advance(by: .seconds(19))
        await Assisted.settle { clock.sleeperCount == 1 }
        #expect(spawner.session.terminationCount == 0)

        spawner.session.emit(Assisted.frame(around: assistedCanary))
        #expect(await outcome.acquiredToken != nil)
    }

    @Test("o relógio da composição de produção é monotônico e conta a suspensão da máquina")
    func theProductionClockIsMonotonicAndCountsSuspension() {
        let acquirer = SetupTokenCredentialAcquirer(discover: { .notFound }, spawner: FakePseudoTerminal())

        #expect(type(of: acquirer) == SetupTokenCredentialAcquirer<ContinuousClock>.self)
        #expect(type(of: acquirer) != SetupTokenCredentialAcquirer<SuspendingClock>.self)
    }

    @Test("os prazos de produção são vinte segundos, três minutos, e dois segundos de carência")
    func theProductionDeadlinesAreTheOnesTheProductPromises() {
        #expect(AssistedSetupTiming.standard.firstOutput == .seconds(20))
        #expect(AssistedSetupTiming.standard.total == .seconds(180))
        #expect(AssistedSetupTiming.standard.terminationGrace == .seconds(2))
    }

    @Test("antes de o filho falar, o único desfecho de espera alcançável é o do silêncio inicial")
    func onlyTheInitialSilenceIsReachableBeforeTheChildSpeaks() async {
        let clock = ManualClock()
        let spawner = FakePseudoTerminal()
        let log = ProgressLog()
        let acquirer = Assisted.acquirer(spawner: spawner, clock: clock)

        async let outcome = acquirer.acquire(onProgress: log.sink)
        await Assisted.settle { clock.sleeperCount == 1 }
        clock.advance(by: .seconds(20))

        #expect(await outcome.unavailability == .silentBeforeAnySign)
        #expect(await log.stages == [.launching])
    }

    @Test("cancelar devolve cancelamento e encerra a condução")
    func cancellingEndsTheConduction() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner)

        let conduction = Task { await acquirer.acquire { _ in } }
        await Assisted.settle { spawner.spawnCount == 1 }
        conduction.cancel()

        #expect(await conduction.value.isCancelled)
        #expect(spawner.session.terminationCount >= 1)
    }

    @Test("credencial que chega depois do cancelamento é descartada sem mudar o desfecho")
    func aLateCredentialAfterCancellationIsDiscarded() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner)

        let conduction = Task { await acquirer.acquire { _ in } }
        await Assisted.settle { spawner.spawnCount == 1 }
        conduction.cancel()
        await Assisted.settle { spawner.session.terminationCount >= 1 }
        spawner.session.emit(Assisted.frame(around: assistedCanary))

        let outcome = await conduction.value
        #expect(outcome.isCancelled)
        #expect(outcome.acquiredToken == nil)
    }

    @Test("credencial que chega depois do prazo vencido é descartada sem mudar o desfecho")
    func aLateCredentialAfterTheDeadlineIsDiscarded() async {
        let clock = ManualClock()
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner, clock: clock)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { clock.sleeperCount == 1 }
        clock.advance(by: .seconds(20))
        await Assisted.settle { spawner.session.terminationCount >= 1 }
        spawner.session.emit(Assisted.frame(around: assistedCanary))

        let settled = await outcome
        #expect(settled.unavailability == .silentBeforeAnySign)
        #expect(settled.acquiredToken == nil)
    }

    @Test("o progresso vai de lançamento a espera de aprovação no primeiro byte, e não repete")
    func progressReachesWaitingOnTheFirstByte() async {
        let spawner = FakePseudoTerminal()
        let log = ProgressLog()
        let acquirer = Assisted.acquirer(spawner: spawner)

        async let outcome = acquirer.acquire(onProgress: log.sink)
        await Assisted.settle { spawner.spawnCount == 1 }
        #expect(await log.stages == [.launching])

        spawner.session.emit("a autorização abriu\r\n")
        await Assisted.settle { await log.stages.count == 2 }
        spawner.session.emit(Assisted.frame(around: assistedCanary))
        _ = await outcome

        #expect(await log.stages == [.launching, .waitingForApproval])
    }

    @Test("duas chamadas concorrentes lançam um único processo")
    func twoConcurrentCallsLaunchASingleProcess() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner)

        async let first = acquirer.acquire { _ in }
        await Assisted.settle { spawner.spawnCount == 1 }
        let second = await acquirer.acquire { _ in }

        spawner.session.emit(Assisted.frame(around: assistedCanary))

        #expect(spawner.spawnCount == 1)
        #expect(second.isCancelled)
        #expect(await first.acquiredToken != nil)
    }

    @Test("o ambiente do filho tem exatamente quatro chaves, todas montadas e nenhuma herdada")
    func theChildEnvironmentHasExactlyFourAssembledKeys() {
        let command = TerminalCommand.setupToken(
            claudeCode: URL(filePath: "/stub/claude"),
            home: URL(filePath: "/Users/quota-bar-test")
        )

        #expect(command.environment.count == 4)
        #expect(command.environment["HOME"] == "/Users/quota-bar-test")
        #expect(command.environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(command.environment["TERM"] == "xterm-256color")
        #expect(command.environment["LANG"] == "en_US.UTF-8")
        #expect(command.arguments == ["setup-token"])
        #expect(command.workingDirectory.path(percentEncoded: false) == "/Users/quota-bar-test")
        #expect(command.window == TerminalWindow.wide)
        #expect(command.window.columns == 512)
        #expect(command.window.rows == 200)
    }

    @Test("credenciais presentes no ambiente de quem desenvolve não atravessam para o filho")
    func credentialsInTheDevelopersEnvironmentDoNotCrossOver() {
        let planted = ["ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_AUTH_TOKEN"]
        for name in planted { setenv(name, assistedCanary, 1) }
        defer { for name in planted { unsetenv(name) } }

        let command = TerminalCommand.setupToken(
            claudeCode: URL(filePath: "/stub/claude"),
            home: URL(filePath: "/Users/quota-bar-test")
        )

        for name in planted {
            #expect(ProcessInfo.processInfo.environment[name] == assistedCanary, "o canário não foi plantado")
            #expect(command.environment[name] == nil)
        }
        #expect(!command.environment.values.contains(assistedCanary))
    }

    @Test("a condução lança o executável descoberto, por caminho absoluto e sem shell")
    func theConductionLaunchesTheDiscoveredExecutable() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(discovery: .stub(path: "/opt/homebrew/bin/claude"), spawner: spawner)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { spawner.spawnCount == 1 }
        spawner.session.emit(Assisted.frame(around: assistedCanary))
        _ = await outcome

        #expect(spawner.lastCommand?.executable.path(percentEncoded: false) == "/opt/homebrew/bin/claude")
        #expect(spawner.lastCommand?.arguments == ["setup-token"])
    }

    @Test("nenhum desfecho nem etapa tem onde carregar a saída do processo conduzido")
    func noOutcomeOrStageHasAnywhereToCarryTheConductedOutput() {
        for cause in AssistedSetupUnavailability.allCases {
            #expect(Mirror(reflecting: cause).children.isEmpty, "\(cause) carrega dado associado")
        }

        for stage in [AssistedSetupProgress.launching, .waitingForApproval] {
            #expect(Mirror(reflecting: stage).children.isEmpty, "\(stage) carrega dado associado")
        }

        for response in [CodeSubmission.delivered, .rejectedAsCredential, .noLiveConduction] {
            #expect(Mirror(reflecting: response).children.isEmpty, "\(response) carrega dado associado")
        }
    }

    @Test("o desfecho que carrega a credencial não é comparável, hashável nem serializável")
    func theOutcomeThatCarriesTheCredentialHasNoLeakingConformance() {
        let outcome: Any = AssistedSetupOutcome.cancelled

        #expect(!(outcome is any Equatable))
        #expect(!(outcome is any Hashable))
        #expect(!(outcome is any Encodable))
        #expect(!(outcome is any Decodable))
    }

    @Test("só os desfechos posteriores à abertura do navegador admitem falar de navegador e de código")
    func onlyOutcomesAfterTheBrowserOpenedMayMentionBrowserAndCode() {
        #expect(AssistedSetupUnavailability.silentBeforeAnySign.mayMentionBrowserOrCode == false)
        #expect(AssistedSetupUnavailability.launchFailed.mayMentionBrowserOrCode == false)
        #expect(AssistedSetupUnavailability.claudeCodeNotFound.mayMentionBrowserOrCode == false)
        #expect(AssistedSetupUnavailability.approvalTimedOut.mayMentionBrowserOrCode)
        #expect(AssistedSetupUnavailability.endedWithoutCredential.mayMentionBrowserOrCode)
        #expect(AssistedSetupUnavailability.refusedByPolicy.mayMentionBrowserOrCode)
    }
}

@Suite("Entrega do código de autorização à condução em curso", .timeLimit(.minutes(1)))
struct CodeSubmissionTests {
    private static let code = "abc123XYZ#estado-da-autorizacao"

    @Test("o código entregue é escrito aparado e com exatamente um retorno")
    func theDeliveredCodeIsTrimmedAndCarriesASingleReturn() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { spawner.spawnCount == 1 }

        #expect(await acquirer.submit(code: "  \n\(Self.code)\n  ") == .delivered)
        #expect(spawner.session.receivedBytes == Array(Self.code.utf8) + [0x0D])

        spawner.session.emit(Assisted.frame(around: assistedCanary))
        #expect(await outcome.acquiredToken != nil)
    }

    @Test("valor com forma de credencial colado no campo do código não vira byte algum")
    func aCredentialShapedValueNeverBecomesAByte() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { spawner.spawnCount == 1 }

        #expect(await acquirer.submit(code: assistedCanary) == .rejectedAsCredential)
        #expect(await acquirer.submit(code: "  \(assistedCanary)  ") == .rejectedAsCredential)
        #expect(spawner.session.receivedBytes.isEmpty)

        spawner.session.endStream()
        #expect(await outcome.acquiredToken == nil)
    }

    @Test("encerrada a condução, a submissão declara que não há condução viva e não escreve nada")
    func aFinishedConductionRefusesTheSubmissionWithoutWriting() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner)

        #expect(await acquirer.submit(code: Self.code) == .noLiveConduction)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { spawner.spawnCount == 1 }
        spawner.session.emit(Assisted.frame(around: assistedCanary))
        _ = await outcome

        #expect(await acquirer.submit(code: Self.code) == .noLiveConduction)
        #expect(spawner.session.receivedBytes.isEmpty)
    }

    @Test("sobre condução morta, a resposta é a ausência de condução, nunca a recusa por forma")
    func livenessIsDecidedBeforeShape() async {
        let acquirer = Assisted.acquirer()

        #expect(await acquirer.submit(code: assistedCanary) == .noLiveConduction)
    }

    @Test("o transporte não retém o código depois de entregá-lo")
    func theTransportRetainsNothingAfterDelivering() async {
        let spawner = FakePseudoTerminal()
        let acquirer = Assisted.acquirer(spawner: spawner)

        async let outcome = acquirer.acquire { _ in }
        await Assisted.settle { spawner.spawnCount == 1 }
        #expect(await acquirer.submit(code: Self.code) == .delivered)

        #expect(await acquirer.outboxIsZeroed)

        var retained = ""
        dump(acquirer, to: &retained, maxDepth: 4)
        #expect(!retained.contains(Self.code))

        spawner.session.endStream()
        _ = await outcome
    }

    @Test("o buffer de escrita reaproveitado fica zerado depois do envio")
    func theReusedWriteBufferIsZeroedAfterSending() {
        let outbox = SecretOutbox()

        let payload = outbox.load(Self.code, terminatedBy: 0x0D)
        #expect(Array(payload) == Array(Self.code.utf8) + [0x0D])
        #expect(!outbox.isZeroed)

        outbox.wipe()
        #expect(outbox.isZeroed)
    }
}
