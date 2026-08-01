import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore
import QuotaBarTransport

@MainActor
@Suite("Superfície de configuração da credencial")
struct CredentialSetupTests {
    @Test("QB-SEC-001 AC-2: a superfície diz o comando, onde colar e como salvar, sem remeter a documentação externa")
    func theSurfaceSaysEverythingInOnePlace() async {
        let content = await Setup.opened().content

        #expect(content.command == "claude setup-token")
        #expect(!content.steps.isEmpty)
        #expect(!content.fieldLabel.isEmpty)
        #expect(!content.saveTitle.isEmpty)
        #expect(content.showsField)

        for line in Setup.text(of: content) {
            #expect(!line.contains("http"), "a superfície remete a documentação externa: \(line)")
            #expect(!line.lowercased().contains("documentação"), "a superfície remete a documentação: \(line)")
        }
    }

    @Test("QB-SEC-001 AC-3: o comando é copiado em uma ação, e nada além dele vai para a área de transferência")
    func theCommandIsCopiedInOneAction() async {
        let clipboard = SpyClipboard()
        let model = await Setup.opened(clipboard: clipboard)

        model.copyCommand()

        #expect(clipboard.copied == ["claude setup-token"])
    }

    @Test("sem Claude Code a pendência vem antes de tudo, e salvar fica indisponível com o motivo dito")
    func withoutClaudeCodeThePreconditionComesFirst() async {
        let content = await Setup.opened(discovery: .notFound).content

        #expect(content.stage == .blockedByPrecondition)
        #expect(content.precondition != nil)
        #expect(content.precondition?.contains("Claude Code") == true)
        #expect(!content.canSave)
        #expect(content.saveDisabledReason != nil)
    }

    @Test("QB-SEC-001 AC-5: instalar o Claude Code libera a superfície sem reiniciar o aplicativo")
    func installingClaudeCodeUnblocksTheSurface() async {
        let discovery = DiscoverySwitch(.notFound)
        let model = CredentialSetupModel(
            store: RecordingCredentialStore(),
            verifier: GatedVerifier(.success),
            acquirer: StubAssistedAcquirer(),
            claudeCode: { await discovery.read() },
            credentialDidChange: CredentialChangeSpy().notify,
            clipboard: SpyClipboard()
        )

        await model.refresh()
        #expect(!model.content.canSave)

        await discovery.set(Setup.installed)
        await model.refresh()

        #expect(model.content.canSave)
        #expect(model.content.precondition == nil)
    }

    @Test("QB-SEC-001 AC-14: sem Claude Code, tentar salvar não grava e declara a pendência")
    func savingWithoutClaudeCodeStoresNothing() async {
        let store = RecordingCredentialStore()
        let verifier = GatedVerifier(.success)
        let model = await Setup.opened(store: store, verifier: verifier, discovery: .notFound)

        await model.save(credentialCanary)

        #expect(await store.storeCount == 0)
        #expect(await verifier.calls == 0)
        #expect(model.stage == .blockedByPrecondition)
        #expect(model.message == CredentialSetupText.message(for: VerificationOutcome.claudeCodeNotFound))
    }

    @Test("QB-SEC-001 AC-7: forma inválida é recusada sem rede e sem gravar, declarando o que se esperava")
    func malformedValueIsRefusedWithoutNetwork() async {
        let store = RecordingCredentialStore()
        let verifier = GatedVerifier(.success)
        let model = await Setup.opened(store: store, verifier: verifier)

        await model.save("sk-ant-api03-uma-chave-do-console")

        #expect(await verifier.calls == 0)
        #expect(await store.storeCount == 0)
        #expect(model.stage == .empty)
        #expect(model.message == CredentialSetupText.malformedValue)
        #expect(model.message?.text.contains("sk-ant-oat01-") == true)
    }

    @Test("QB-SEC-001 AC-8: espaços e quebras de linha em volta não custam uma tentativa")
    func surroundingWhitespaceIsIgnored() async {
        let store = RecordingCredentialStore()
        let model = await Setup.opened(store: store)

        await model.save("  \n\(credentialCanary)\n  ")

        #expect(model.stage == .configured)
        #expect(await store.holds(credentialCanary))
    }

    @Test("QB-SEC-001 AC-9: campo vazio não grava, não pede rede e não muda o estado da superfície")
    func emptyFieldChangesNothing() async {
        let store = RecordingCredentialStore()
        let verifier = GatedVerifier(.success)
        let model = await Setup.opened(store: store, verifier: verifier)
        let before = model.content

        await model.save("")
        await model.save("   \n ")

        #expect(await verifier.calls == 0)
        #expect(await store.storeCount == 0)
        #expect(model.content == before)
    }

    @Test("QB-SEC-001 AC-10: a superfície só passa a Configurada depois do desfecho da verificação")
    func successOnlyAfterRealVerification() async {
        let store = RecordingCredentialStore()
        let verifier = GatedVerifier(.success, gated: true)
        let model = await Setup.opened(store: store, verifier: verifier)

        async let saving: Void = model.save(credentialCanary)
        await Setup.settle(model, until: .verifying)
        await Setup.settle(verifier, untilCalled: 1)

        #expect(model.stage == .verifying)
        #expect(await store.storeCount == 0)

        await verifier.open()
        await saving

        #expect(model.stage == .configured)
        #expect(await store.holds(credentialCanary))
    }

    @Test("QB-SEC-001 AC-11: credencial recusada e credencial expirada não gravam, e a pendência continua")
    func refusedAndExpiredDoNotStore() async {
        for outcome in [VerificationOutcome.credentialRejected, .credentialExpired] {
            let store = RecordingCredentialStore()
            let model = await Setup.opened(store: store, verifier: GatedVerifier(outcome))

            await model.save(credentialCanary)

            #expect(await store.storeCount == 0, "gravou em \(outcome)")
            #expect(await store.isPopulated == false)
            #expect(model.stage == .refused)
            #expect(model.hasStoredCredential == false)
        }
    }

    @Test("QB-SEC-001 AC-12: bloqueio por política grava e a superfície declara o bloqueio")
    func policyBlockStoresAndDeclares() async {
        let store = RecordingCredentialStore()
        let model = await Setup.opened(store: store, verifier: GatedVerifier(.blockedByPolicy))

        await model.save(credentialCanary)

        #expect(await store.holds(credentialCanary))
        #expect(model.stage == .configuredWithReservation)
        #expect(model.message?.text.contains("barrou") == true)
        #expect(model.content.removeTitle != nil)
        #expect(model.content.replaceTitle != nil)
    }

    @Test("QB-SEC-001 AC-13: falha de comunicação grava e declara que o aplicativo tentará por conta própria")
    func communicationFailureStoresAndPromisesToRetry() async {
        let store = RecordingCredentialStore()
        let model = await Setup.opened(store: store, verifier: GatedVerifier(.communicationFailure))

        await model.save(credentialCanary)

        #expect(await store.holds(credentialCanary))
        #expect(model.stage == .configuredWithReservation)
        #expect(model.message?.action == .waitForNetwork)
        #expect(model.message?.text.contains("tentará") == true)
    }

    @Test("QB-SEC-001 AC-28: resposta inesperada não grava e não acusa a credencial")
    func unexpectedResponseNeitherStoresNorAccuses() async {
        let store = RecordingCredentialStore()
        let model = await Setup.opened(store: store, verifier: GatedVerifier(.unexpectedResponse))

        await model.save(credentialCanary)

        #expect(await store.storeCount == 0)
        #expect(model.stage == .refused)
        #expect(model.message?.action == .tryAgain)

        let text = model.message?.text.lowercased() ?? ""
        #expect(!text.contains("inválida"))
        #expect(!text.contains("recusada"))
        #expect(!text.contains("expirou"))
    }

    @Test("QB-SEC-001 AC-29: a gravação segue a tabela dos sete desfechos, sem reimplementá-la")
    func persistenceFollowsTheOutcomeTable() async {
        for outcome in VerificationOutcome.allCases {
            let store = RecordingCredentialStore()
            let model = await Setup.opened(store: store, verifier: GatedVerifier(outcome))

            await model.save(credentialCanary)

            #expect(
                await store.isPopulated == outcome.shouldPersist,
                "\(outcome) divergiu de shouldPersist == \(outcome.shouldPersist)"
            )
        }
    }

    @Test("QB-SEC-001 AC-26: uma verificação por vez — salvar de novo não dispara requisição adicional")
    func onlyOneVerificationAtATime() async {
        let verifier = GatedVerifier(.success, gated: true)
        let model = await Setup.opened(verifier: verifier)

        async let saving: Void = model.save(credentialCanary)
        await Setup.settle(model, until: .verifying)
        await Setup.settle(verifier, untilCalled: 1)

        #expect(await verifier.calls == 1)

        await model.save(credentialCanary)
        #expect(await verifier.calls == 1)

        await verifier.open()
        await saving

        #expect(await verifier.calls == 1)
        #expect(model.stage == .configured)
    }

    @Test("QB-SEC-001 AC-27: fechar durante a verificação não grava pelas costas e preserva o estado anterior")
    func closingDuringVerificationStoresNothing() async {
        let store = RecordingCredentialStore()
        let verifier = GatedVerifier(.success, gated: true)
        let model = await Setup.opened(store: store, verifier: verifier)

        async let saving: Void = model.save(credentialCanary)
        await Setup.settle(model, until: .verifying)
        await Setup.settle(verifier, untilCalled: 1)

        model.cancel()
        await verifier.open()
        await saving

        #expect(await store.storeCount == 0)
        #expect(await store.isPopulated == false)
        #expect(model.stage == .empty)
        #expect(model.message == nil)
    }

    @Test("QB-SEC-001 AC-17: configurada, a superfície informa a existência e oferece substituir e remover")
    func configuredShowsExistenceAndItsTwoActions() async {
        let store = RecordingCredentialStore(seeded: credentialCanary)
        let model = await Setup.opened(store: store)
        let content = model.content

        #expect(content.stage == .configured)
        #expect(content.configuredNotice != nil)
        #expect(content.replaceTitle != nil)
        #expect(content.removeTitle != nil)
        #expect(!content.showsField)
        #expect(await store.loadCount == 0, "a superfície leu o valor guardado")
        #expect(!Setup.text(of: content).contains { $0.contains(credentialCanary) })
    }

    @Test("QB-SEC-001 AC-18: substituição malsucedida preserva a credencial anterior")
    func failedReplacementPreservesThePreviousCredential() async {
        let store = RecordingCredentialStore(seeded: credentialCanary)
        let model = await Setup.opened(store: store, verifier: GatedVerifier(.credentialRejected))

        model.beginReplacement()
        #expect(model.content.showsField)

        await model.save("sk-ant-oat01-outro-valor-qualquer")

        #expect(await store.holds(credentialCanary))
        #expect(model.stage == .configured)
        #expect(model.hasStoredCredential)
        #expect(model.message?.action == .generateNewCredential)
    }

    @Test("QB-API-001 REQ-18: só a mudança do que está guardado avisa a sondagem")
    func onlyAChangeOfTheStoredCredentialAnnouncesItself() async {
        let stored = CredentialChangeSpy()
        await Setup.opened(credentialDidChange: stored).save(credentialCanary)
        #expect(await stored.notifications == 1)

        let refused = CredentialChangeSpy()
        let rejecting = await Setup.opened(verifier: GatedVerifier(.credentialRejected), credentialDidChange: refused)
        await rejecting.save(credentialCanary)
        #expect(await refused.notifications == 0)

        let unwritten = CredentialChangeSpy()
        let store = RecordingCredentialStore()
        await store.refuseWrites(with: .interactionNotAllowed)
        await Setup.opened(store: store, credentialDidChange: unwritten).save(credentialCanary)
        #expect(await unwritten.notifications == 0)
    }

    @Test("QB-SEC-001 REQ-12: remover a credencial avisa a sondagem, que passa a declarar a pendência")
    func removingTheCredentialAnnouncesItself() async {
        let spy = CredentialChangeSpy()
        let model = await Setup.opened(
            store: RecordingCredentialStore(seeded: credentialCanary),
            credentialDidChange: spy
        )

        await model.remove()

        #expect(await spy.notifications == 1)
    }

    @Test("QB-SEC-001 AC-19: remover apaga de fato e devolve a superfície à pendência")
    func removalDeletesTheItem() async {
        let store = RecordingCredentialStore(seeded: credentialCanary)
        let model = await Setup.opened(store: store)

        await model.remove()

        #expect(await store.isPopulated == false)
        #expect(model.stage == .empty)
        #expect(model.hasStoredCredential == false)

        await model.refresh()
        #expect(model.stage == .empty)
        #expect(model.content.configuredNotice == nil)
    }

    @Test("QB-SEC-001 AC-15: os sete desfechos e as falhas de Keychain têm mensagens distintas e acionáveis")
    func everyOutcomeHasItsOwnActionableMessage() {
        let outcomes = VerificationOutcome.allCases.map(CredentialSetupText.message(for:))
        let keychain = [
            CredentialSetupText.keychainWriteRefused,
            CredentialSetupText.keychainReadRefused,
            CredentialSetupText.keychainRemoveRefused
        ]
        let all = outcomes + keychain + [CredentialSetupText.malformedValue, CredentialSetupText.removed]

        #expect(outcomes.count == 7)
        #expect(Set(all.map(\.text)).count == all.count)
        #expect(all.allSatisfy { !$0.text.isEmpty })
        #expect(CredentialSetupText.message(for: VerificationOutcome.claudeCodeNotFound).action == .installClaudeCode)
        #expect(CredentialSetupText.message(for: .credentialRejected).action == .generateNewCredential)
        #expect(CredentialSetupText.message(for: .credentialExpired).action == .generateNewCredential)
        #expect(CredentialSetupText.message(for: .communicationFailure).action == .waitForNetwork)
        #expect(CredentialSetupText.message(for: .unexpectedResponse).action == .tryAgain)
        #expect(CredentialSetupText.message(for: .blockedByPolicy).action == .nothingToDo)
        #expect(CredentialSetupText.message(for: .success).action == .nothingToDo)
    }

    @Test("QB-SEC-001 AC-16: a recusa sem evidência de expiração usa a mensagem única, sem afirmar expiração")
    func refusalWithoutEvidenceDoesNotClaimExpiration() {
        let refusal = CredentialSetupText.message(for: .credentialRejected)

        #expect(refusal.text.contains("não é mais aceita"))
        #expect(refusal.text.contains("Gere uma nova"))
        #expect(!refusal.text.lowercased().contains("expir"))
    }

    @Test("QB-SEC-001 AC-22: falha de Keychain ao gravar tem mensagem própria e não acusa a credencial")
    func keychainWriteFailureIsNotAnInvalidCredential() async {
        let store = RecordingCredentialStore()
        await store.refuseWrites(with: .interactionNotAllowed)
        let model = await Setup.opened(store: store)

        await model.save(credentialCanary)

        #expect(await store.isPopulated == false)
        #expect(model.message == CredentialSetupText.keychainWriteRefused)
        #expect(model.stage == .empty)

        let credentialMessages = [
            CredentialSetupText.message(for: .credentialRejected).text,
            CredentialSetupText.message(for: .credentialExpired).text,
            CredentialSetupText.message(for: .blockedByPolicy).text
        ]
        #expect(!credentialMessages.contains(CredentialSetupText.keychainWriteRefused.text))
        #expect(!CredentialSetupText.keychainWriteRefused.text.lowercased().contains("inválida"))
    }

    @Test("QB-SEC-001 AC-22: falha de Keychain ao ler tem mensagem própria, distinta de ausente e de recusada")
    func keychainReadFailureHasItsOwnMessage() async {
        let store = RecordingCredentialStore(seeded: credentialCanary)
        await store.refusePresenceCheck(with: .interactionNotAllowed)
        let model = await Setup.opened(store: store)

        #expect(model.message == CredentialSetupText.keychainReadRefused)
        #expect(!CredentialSetupText.keychainReadRefused.text.lowercased().contains("inválida"))
        #expect(CredentialSetupText.keychainReadRefused.text != CredentialSetupText.keychainWriteRefused.text)
    }

    @Test("QB-SEC-001 REQ-12: Keychain que recusa remover não declara remoção")
    func keychainRemovalFailureKeepsReportingConfigured() async {
        let store = RecordingCredentialStore(seeded: credentialCanary)
        await store.refuseRemoval(with: .interactionNotAllowed)
        let model = await Setup.opened(store: store)

        await model.remove()

        #expect(await store.isPopulated)
        #expect(model.stage == .configured)
        #expect(model.hasStoredCredential)
        #expect(model.message == CredentialSetupText.keychainRemoveRefused)
    }

    @Test("QB-SEC-001 AC-6 e QB-SEC-001 AC-21: nenhuma superfície da configuração exibe o valor, em nenhum estado")
    func noSurfaceEverShowsTheValue() async {
        let clipboard = SpyClipboard()

        for outcome in VerificationOutcome.allCases {
            let model = await Setup.opened(verifier: GatedVerifier(outcome), clipboard: clipboard)
            await model.save(credentialCanary)

            for line in Setup.text(of: model.content) {
                #expect(!line.contains(credentialCanary), "vazou em \(outcome): \(line)")
                #expect(!line.contains("CANARIO"), "vazou parcialmente em \(outcome): \(line)")
            }
        }

        let blocked = await Setup.opened(discovery: .notFound)
        await blocked.save(credentialCanary)
        for line in Setup.text(of: blocked.content) {
            #expect(!line.contains(credentialCanary))
        }

        #expect(clipboard.copied.isEmpty)
    }

    @Test("QB-SEC-001 AC-21: o modelo da superfície não guarda cópia do valor depois de salvar")
    func theModelKeepsNoCopyOfTheValue() async {
        let model = await Setup.opened()

        await model.save(credentialCanary)

        var ownState = ""
        dump(model, to: &ownState, maxDepth: 1)

        #expect(model.stage == .configured)
        #expect(!ownState.contains("CANARIO"))
        #expect(!ownState.contains("sk-ant-oat01-"))
    }

    @Test("QB-SEC-001 AC-24: o portador não vira texto em nenhuma das três formas")
    func theTokenNeverBecomesText() throws {
        let token = try #require(SubscriptionToken(pasted: credentialCanary))

        #expect("\(token)" == "SubscriptionToken(redigido)")
        #expect(String(describing: token) == "SubscriptionToken(redigido)")
        #expect(String(reflecting: token) == "SubscriptionToken(redigido)")
        #expect(!"\(token)".contains("CANARIO"))
    }

    @Test("QB-APP-002 REQ-19: o texto da superfície tem contraste suficiente sobre a sua superfície")
    func setupSurfaceKeepsTheRequiredContrast() {
        #expect(Contrast.ratio(Palette.text, PanelSurface.background) >= Contrast.minimumRatio)
        #expect(Contrast.ratio(Palette.textMuted, PanelSurface.background) >= Contrast.minimumRatio)
        #expect(Contrast.ratio(Palette.text, PanelSurface.card) >= Contrast.minimumRatio)
        #expect(Contrast.ratio(Palette.textMuted, PanelSurface.card) >= Contrast.minimumRatio)
    }
}
