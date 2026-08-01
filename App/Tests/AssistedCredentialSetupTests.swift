import Foundation
import QuotaBarCore
import QuotaBarTransport
import Testing

@testable import QuotaBar

private let authorizationCode = "abc123XYZ#estado-da-autorizacao"

@MainActor
@Suite("Configuração da credencial pela via assistida", .timeLimit(.minutes(1)))
struct AssistedCredentialSetupTests {
    @Test("sem credencial, a via assistida é a ação em evidência e a via manual está ao lado, pronta")
    func withoutACredentialBothWaysAreOffered() async {
        let content = await Setup.opened().content

        #expect(content.assistTitle != nil)
        #expect(content.assistUnavailableReason == nil)
        #expect(content.showsField)
        #expect(content.canSave)
        #expect(content.command == "claude setup-token")
        #expect(content.saveDisabledReason == nil)
    }

    @Test("a ação assistida aparece sem rótulo de experimento e sem preferência que a habilite")
    func theAssistedActionCarriesNoExperimentLabel() async {
        let content = await Setup.opened().content
        let discouraging = ["experimento", "experimental", "beta", "pode não funcionar", "instável"]

        for line in Setup.text(of: content) {
            for word in discouraging {
                #expect(!line.lowercased().contains(word), "a superfície desencoraja a via assistida: \(line)")
            }
        }
        #expect(content.assistTitle?.contains("navegador") == true)
    }

    @Test("a via é oferecida com qualquer versão encontrada, inclusive uma que o aplicativo não reconhece")
    func anyDiscoveredVersionOffersTheAssistedWay() async {
        let versions = ["2.1.220", "0.0.1-desconhecida", ""]

        for version in versions {
            let discovery = ClaudeCodeDiscovery.installed(
                ClaudeCodeInstallation(
                    version: version,
                    executable: ClaudeCodeExecutable(path: "/stub/claude", modifiedAt: .distantPast, size: 1)
                )
            )
            let content = await Setup.opened(discovery: discovery).content

            #expect(content.assistTitle != nil, "a versão \(version) escondeu a via assistida")
        }
    }

    @Test("do clique à credencial guardada, sem nenhuma digitação e com uma única requisição")
    func fromTheClickToTheStoredCredentialWithoutTyping() async {
        let store = RecordingCredentialStore()
        let verifier = GatedVerifier(.success)
        let changed = CredentialChangeSpy()
        let model = await Setup.opened(store: store, verifier: verifier, credentialDidChange: changed)

        await model.assist()

        #expect(model.stage == .configured)
        #expect(await store.holds(credentialCanary))
        #expect(await verifier.calls == 1)
        #expect(await changed.notifications == 1)
        #expect(model.hasStoredCredential)
    }

    @Test("a superfície declara o custo em cota antes de a via assistida começar")
    func theSurfaceDeclaresTheQuotaCostBeforeStarting() async {
        let content = await Setup.opened().content

        #expect(content.costNotice != nil)
        #expect(content.costNotice?.contains("uma requisição") == true)
        #expect(content.costNotice?.contains("cota") == true)
    }

    @Test("nada começa sozinho: abrir a superfície em qualquer pendência não conduz nada")
    func nothingStartsOnItsOwn() async {
        let acquirer = StubAssistedAcquirer()

        let pending = await Setup.opened(acquirer: acquirer)
        #expect(await acquirer.acquisitions == 0)

        let expired = await Setup.opened(verifier: GatedVerifier(.credentialExpired), acquirer: acquirer)
        await expired.save(credentialCanary)
        #expect(await acquirer.acquisitions == 0)

        let refused = await Setup.opened(verifier: GatedVerifier(.credentialRejected), acquirer: acquirer)
        await refused.save(credentialCanary)
        #expect(await acquirer.acquisitions == 0)

        let stored = RecordingCredentialStore(seeded: credentialCanary)
        let removing = await Setup.opened(store: stored, acquirer: acquirer)
        await removing.remove()
        await removing.refresh()
        #expect(await acquirer.acquisitions == 0)
        #expect(pending.stage == .empty)
    }

    @Test("a credencial obtida passa pela mesma tabela de gravação da via manual, desfecho a desfecho")
    func theObtainedCredentialFollowsTheSamePersistenceTable() async {
        for outcome in VerificationOutcome.allCases {
            let store = RecordingCredentialStore()
            let model = await Setup.opened(store: store, verifier: GatedVerifier(outcome))

            await model.assist()

            #expect(
                await store.isPopulated == outcome.shouldPersist,
                "a via assistida divergiu da tabela em \(outcome)"
            )
        }
    }

    @Test("nada é gravado antes do desfecho da verificação, mesmo com a credencial já em mãos")
    func nothingIsStoredBeforeTheVerificationSettles() async {
        let store = RecordingCredentialStore()
        let verifier = GatedVerifier(.success, gated: true)
        let model = await Setup.opened(store: store, verifier: verifier)

        async let assisting: Void = model.assist()
        await Setup.settle(model, until: .verifying)
        await Setup.settle(verifier, untilCalled: 1)

        #expect(model.stage == .verifying)
        #expect(await store.storeCount == 0)

        await verifier.open()
        await assisting

        #expect(model.stage == .configured)
    }

    @Test("durante a espera a superfície declara a etapa em texto e oferece cancelar")
    func theWaitIsDeclaredInWords() async {
        let acquirer = StubAssistedAcquirer(gated: true)
        let model = await Setup.opened(acquirer: acquirer)

        async let assisting: Void = model.assist()
        await Setup.settle(model, until: .assisting)
        await Setup.settle(untilTrue: { model.waiting == .waitingForApproval })

        let content = model.content
        #expect(content.waitingNotice?.contains("navegador") == true)
        #expect(content.waitingNotice?.contains("aguarda") == true)
        #expect(content.cancelTitle != nil)

        await acquirer.release()
        await assisting
    }

    @Test("durante a espera a via manual continua desenhada, e salvar fica indisponível com o motivo dito")
    func theManualWayStaysDrawnWhileTheAssistedOneRuns() async {
        let acquirer = StubAssistedAcquirer(gated: true)
        let model = await Setup.opened(acquirer: acquirer)

        async let assisting: Void = model.assist()
        await Setup.settle(model, until: .assisting)

        let content = model.content
        #expect(content.showsField)
        #expect(content.command == "claude setup-token")
        #expect(!content.saveTitle.isEmpty)
        #expect(!content.canSave)
        #expect(content.saveDisabledReason != nil)
        #expect(content.codeFieldLabel != nil)

        await acquirer.release()
        await assisting
    }

    @Test("acionar a via assistida de novo durante a espera não inicia uma segunda condução")
    func retriggeringDuringTheWaitStartsNothingNew() async {
        let acquirer = StubAssistedAcquirer(gated: true)
        let model = await Setup.opened(acquirer: acquirer)

        async let assisting: Void = model.assist()
        await Setup.settle(model, until: .assisting)
        await Setup.settle(acquirer, untilAcquisitions: 1)

        await model.assist()
        await model.save(credentialCanary)

        #expect(await acquirer.acquisitions == 1)
        #expect(model.stage == .assisting)

        await acquirer.release()
        await assisting
    }

    @Test("cancelar durante a espera não grava nada, devolve o estado anterior e não acusa ninguém")
    func cancellingStoresNothingAndBlamesNobody() async {
        let store = RecordingCredentialStore()
        let acquirer = StubAssistedAcquirer(gated: true)
        let model = await Setup.opened(store: store, acquirer: acquirer)

        async let assisting: Void = model.assist()
        await Setup.settle(model, until: .assisting)
        model.cancel()
        await assisting

        #expect(model.stage == .empty)
        #expect(model.message == nil)
        #expect(await store.storeCount == 0)
        #expect(model.content.codeFieldLabel == nil)
    }

    @Test("cancelar a substituição assistida preserva a credencial que já funcionava")
    func cancellingAReplacementPreservesTheWorkingCredential() async {
        let store = RecordingCredentialStore(seeded: credentialCanary)
        let acquirer = StubAssistedAcquirer(gated: true)
        let model = await Setup.opened(store: store, acquirer: acquirer)

        async let assisting: Void = model.assist()
        await Setup.settle(model, until: .assisting)
        model.cancel()
        await assisting

        #expect(model.stage == .configured)
        #expect(await store.holds(credentialCanary))
        #expect(model.message == nil)
    }

    @Test("prazo vencido e recusa durante a substituição preservam a credencial anterior")
    func anExpiredDeadlineOrARefusalPreservesThePreviousCredential() async {
        let store = RecordingCredentialStore(seeded: credentialCanary)
        let timedOut = await Setup.opened(store: store, acquirer: StubAssistedAcquirer(.unavailable(.approvalTimedOut)))

        await timedOut.assist()

        #expect(timedOut.stage == .configured)
        #expect(await store.holds(credentialCanary))

        let refused = await Setup.opened(
            store: store,
            verifier: GatedVerifier(.credentialRejected),
            acquirer: StubAssistedAcquirer(.obtains("sk-ant-oat01-outro-valor-qualquer-mesmo"))
        )

        await refused.assist()

        #expect(refused.stage == .configured)
        #expect(await store.holds(credentialCanary))
    }

    @Test("todo insucesso da via assistida deixa a via manual pronta na mesma superfície")
    func everyFailureLandsOnTheManualWay() async {
        let causes = AssistedSetupUnavailability.allCases.filter { $0 != .claudeCodeNotFound }

        for cause in causes {
            let store = RecordingCredentialStore()
            let verifier = GatedVerifier(.success)
            let model = await Setup.opened(store: store, verifier: verifier, acquirer: StubAssistedAcquirer(.unavailable(cause)))

            await model.assist()

            #expect(model.stage == .empty, "\(cause) não devolveu a superfície ao estado anterior")
            #expect(model.content.showsField, "\(cause) escondeu o campo da via manual")
            #expect(model.content.canSave, "\(cause) deixou salvar indisponível")
            #expect(model.content.command == "claude setup-token")
            #expect(model.content.assistTitle != nil, "\(cause) removeu a chance de tentar de novo")
            #expect(await store.storeCount == 0)
            #expect(await verifier.calls == 0, "\(cause) gastou uma requisição de cota")
            #expect(model.message != nil, "\(cause) não explicou o que houve")
        }
    }

    @Test("resultado assistido reprovado na forma não vira tarefa da pessoa nem gasta requisição")
    func aResultRejectedByShapeNeverBecomesTheUsersProblem() async {
        let store = RecordingCredentialStore()
        let verifier = GatedVerifier(.success)
        let model = await Setup.opened(
            store: store,
            verifier: verifier,
            acquirer: StubAssistedAcquirer(.obtains("valor-que-nao-tem-a-forma-esperada"))
        )

        await model.assist()

        #expect(await store.storeCount == 0)
        #expect(await verifier.calls == 0)
        #expect(model.content.showsField)
        #expect(model.message?.text.lowercased().contains("corrija") == false)
    }

    @Test("nenhuma mensagem da via assistida culpa a pessoa, e todas nomeiam uma saída")
    func noAssistedMessageBlamesThePerson() async {
        let messages = AssistedSetupUnavailability.allCases.map(CredentialSetupText.message(for:))
            + [CredentialSetupText.assistedCredentialRefused]
        let blaming = ["você", "seu erro", "sua culpa", "errou"]

        for message in messages {
            for word in blaming {
                #expect(!message.text.lowercased().contains(word), "a mensagem culpa quem usa: \(message.text)")
            }
            let namesAWayOut = message.text.contains("tentar") || message.text.contains("Instale")
            #expect(namesAWayOut, "a mensagem não nomeia saída nenhuma: \(message.text)")
        }
        #expect(Set(messages.map(\.text)).count == messages.count)
    }

    @Test("a recusa de uma credencial obtida pela via assistida não manda ninguém para o terminal")
    func anAssistedCredentialRefusalNeverSendsAnyoneToTheTerminal() async {
        let model = await Setup.opened(verifier: GatedVerifier(.credentialRejected))

        await model.assist()

        #expect(model.message == CredentialSetupText.assistedCredentialRefused)
        #expect(model.message?.text.contains("claude setup-token") == false)
        #expect(model.message?.text.contains("Terminal") == false)
        #expect(model.message != CredentialSetupText.message(for: .credentialRejected))
    }

    @Test("a mensagem de silêncio inicial não menciona a pessoa, o navegador nem código algum")
    func theInitialSilenceMessageMentionsNeitherBrowserNorCode() {
        let silence = CredentialSetupText.message(for: .silentBeforeAnySign)
        let timedOut = CredentialSetupText.message(for: .approvalTimedOut)

        #expect(!silence.text.lowercased().contains("navegador"))
        #expect(!silence.text.lowercased().contains("código"))
        #expect(!silence.text.lowercased().contains("você"))
        #expect(silence.text != timedOut.text)
        #expect(silence.text.contains("não chegou a começar"))
    }

    @Test("a mensagem posterior à abertura do navegador nomeia o caso do código e onde ele entrava")
    func theMessageAfterTheBrowserOpenedNamesTheCodeCase() {
        for cause in AssistedSetupUnavailability.allCases where cause.mayMentionBrowserOrCode {
            let text = CredentialSetupText.message(for: cause).text

            #expect(text.contains("navegador"), "\(cause) não nomeia o navegador")
            #expect(text.contains("código"), "\(cause) não nomeia o código")
            #expect(text.contains("não há terminal"), "\(cause) não diz que não há terminal")
        }

        for cause in AssistedSetupUnavailability.allCases where !cause.mayMentionBrowserOrCode {
            let text = CredentialSetupText.message(for: cause).text.lowercased()

            #expect(!text.contains("navegador"), "\(cause) menciona o navegador")
            #expect(!text.contains("código"), "\(cause) menciona o código")
        }
    }

    @Test("a mensagem do prazo total não afirma o que a pessoa fez nem que nada foi criado do outro lado")
    func theTotalDeadlineMessageAssertsNeitherFault() {
        let text = CredentialSetupText.message(for: .approvalTimedOut).text

        #expect(text.contains("parou de esperar"))
        #expect(text.contains("não dá para afirmar que nada"))
        #expect(!text.lowercased().contains("você"))
    }

    @Test("o código colado durante a espera é entregue à condução e a configuração conclui")
    func thePastedCodeIsDeliveredAndTheConfigurationCompletes() async {
        let store = RecordingCredentialStore()
        let acquirer = StubAssistedAcquirer(gated: true)
        let model = await Setup.opened(store: store, acquirer: acquirer)

        async let assisting: Void = model.assist()
        await Setup.settle(model, until: .assisting)

        await model.submitCode("  \n\(authorizationCode)\n  ")
        #expect(await acquirer.submittedCodes == ["  \n\(authorizationCode)\n  "])

        await acquirer.release()
        await assisting

        #expect(model.stage == .configured)
        #expect(await store.holds(credentialCanary))
    }

    @Test("encerrada a espera, o lugar de colar o código deixa de existir em todos os desfechos")
    func theCodeFieldDisappearsWithTheEndOfTheWait() async {
        let successful = await Setup.opened()
        await successful.assist()
        #expect(successful.content.codeFieldLabel == nil)

        for cause in AssistedSetupUnavailability.allCases {
            let model = await Setup.opened(acquirer: StubAssistedAcquirer(.unavailable(cause)))
            await model.assist()

            #expect(model.content.codeFieldLabel == nil, "\(cause) continuou pedindo o código")
            #expect(model.message?.text.contains("cole") == false, "\(cause) pede uma colagem sem efeito")
        }
    }

    @Test("valor com a forma da credencial colado no campo do código é reconhecido e aponta o campo certo")
    func aCredentialInTheCodeFieldIsRecognised() async {
        let acquirer = StubAssistedAcquirer(gated: true, answersSubmissionWith: .rejectedAsCredential)
        let model = await Setup.opened(acquirer: acquirer)

        async let assisting: Void = model.assist()
        await Setup.settle(model, until: .assisting)

        await model.submitCode(credentialCanary)

        #expect(await acquirer.submittedCodes.isEmpty)
        #expect(model.message == CredentialSetupText.credentialInCodeField)
        #expect(model.message?.text.contains("o lugar dele é o campo da credencial") == true)
        #expect(model.message?.text.contains("o lugar dele é o campo do código") == false)
        #expect(model.stage == .assisting)

        await acquirer.release()
        await assisting
    }

    @Test("código colado no campo da credencial é recusado pela forma, sem rede, apontando o campo certo")
    func aCodeInTheCredentialFieldIsRecognised() async {
        let store = RecordingCredentialStore()
        let verifier = GatedVerifier(.success)
        let model = await Setup.opened(store: store, verifier: verifier)

        await model.save(authorizationCode)

        #expect(await verifier.calls == 0)
        #expect(await store.storeCount == 0)
        #expect(model.message == CredentialSetupText.codeInCredentialField)
        #expect(model.message?.text.contains("o lugar dele é o campo do código") == true)
        #expect(model.message?.text.contains("o lugar dele é o campo da credencial") == false)
        #expect(model.message != CredentialSetupText.malformedValue)
    }

    @Test("sem Claude Code a via assistida não é oferecida, e o motivo é dito em vez de um botão inerte")
    func withoutClaudeCodeTheAssistedWayIsNotOfferedAndTheReasonIsSaid() async {
        let content = await Setup.opened(discovery: .notFound).content

        #expect(content.assistTitle == nil)
        #expect(content.assistUnavailableReason?.contains("Claude Code") == true)
        #expect(content.showsField)
        #expect(!content.canSave)
        #expect(content.saveDisabledReason != nil)
        #expect(content.precondition?.contains("Instale o Claude Code") == true)
    }

    @Test("Claude Code desinstalado durante a espera devolve a pendência declarada, sem gravar")
    func claudeCodeVanishingDuringTheWaitDeclaresThePendency() async {
        let store = RecordingCredentialStore()
        let model = await Setup.opened(
            store: store,
            acquirer: StubAssistedAcquirer(.unavailable(.claudeCodeNotFound))
        )

        await model.assist()

        #expect(model.stage == .blockedByPrecondition)
        #expect(model.content.precondition != nil)
        #expect(model.content.assistTitle == nil)
        #expect(model.message?.action == .installClaudeCode)
        #expect(await store.storeCount == 0)
    }

    @Test("nem o canário nem o código aparecem em qualquer superfície durante o percurso assistido")
    func neitherTheCredentialNorTheCodeReachAnySurface() async {
        let clipboard = SpyClipboard()

        for outcome in VerificationOutcome.allCases {
            let model = await Setup.opened(verifier: GatedVerifier(outcome), clipboard: clipboard)
            await model.assist()

            for line in Setup.text(of: model.content) {
                #expect(!line.contains(credentialCanary), "a credencial vazou em \(outcome): \(line)")
                #expect(!line.contains("CANARIO"), "a credencial vazou em parte em \(outcome): \(line)")
            }
        }

        let acquirer = StubAssistedAcquirer(gated: true)
        let model = await Setup.opened(acquirer: acquirer)
        async let assisting: Void = model.assist()
        await Setup.settle(model, until: .assisting)
        await model.submitCode(authorizationCode)

        for line in Setup.text(of: model.content) {
            #expect(!line.contains(authorizationCode), "o código vazou para a superfície: \(line)")
        }

        var retained = ""
        dump(model, to: &retained, maxDepth: 2)
        #expect(!retained.contains(authorizationCode))
        #expect(!retained.contains("CANARIO"))
        #expect(clipboard.copied.isEmpty)

        await acquirer.release()
        await assisting
    }

    @Test("a credencial obtida não é oferecida para cópia quando o Keychain recusa guardá-la")
    func aRefusedKeychainNeverOffersTheCredentialForCopying() async {
        let store = RecordingCredentialStore()
        await store.refuseWrites(with: .interactionNotAllowed)
        let clipboard = SpyClipboard()
        let model = await Setup.opened(store: store, clipboard: clipboard)

        await model.assist()

        #expect(model.message == CredentialSetupText.keychainWriteRefused)
        #expect(clipboard.copied.isEmpty)
        for line in Setup.text(of: model.content) {
            #expect(!line.contains(credentialCanary))
        }
    }
}
