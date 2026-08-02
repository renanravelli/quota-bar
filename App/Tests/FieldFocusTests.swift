import Foundation
import QuotaBarCore
import Testing

@testable import QuotaBar

@MainActor
private final class ForegroundRequests: ApplicationActivating {
    private(set) var count = 0

    func requestActivation() {
        count += 1
    }
}

@MainActor
private func reachOffering(_ content: CredentialSetupContent, keyWindow: Bool = true) -> KeyboardReach {
    let reach = KeyboardReach(application: ForegroundRequests())
    reach.observed(keyWindow: keyWindow)
    reach.offers(content.focusableFields)
    return reach
}

@MainActor
@Suite("Foco do campo e cursor honesto", .timeLimit(.minutes(1)))
struct FieldFocusTests {
    @Test("o campo da credencial nasce focado quando a superfície é apresentada")
    func theCredentialFieldIsBornFocused() async {
        let reach = await reachOffering(Setup.opened().content)

        #expect(reach.focusedField == .credential)
    }

    @Test("com a via assistida esperando, quem nasce focado é o campo do código do navegador")
    func theBrowserCodeFieldIsTheOneBornFocusedDuringTheWait() async {
        let acquirer = StubAssistedAcquirer(gated: true)
        let model = await Setup.opened(acquirer: acquirer)

        async let assisting: Void = model.assist()
        await Setup.settle(model, until: .assisting)

        let reach = reachOffering(model.content)
        #expect(reach.focusedField == .authorizationCode)

        await acquirer.release()
        await assisting
    }

    @Test("enquanto a verificação corre nenhum campo aparece focado")
    func noFieldLooksFocusedWhileTheVerificationRuns() async {
        let verifier = GatedVerifier(.success, gated: true)
        let model = await Setup.opened(verifier: verifier)

        async let saving: Void = model.save(credentialCanary)
        await Setup.settle(model, until: .verifying)

        let reach = reachOffering(model.content)
        #expect(reach.focusedField == nil)

        await verifier.open()
        await saving
    }

    @Test("com a credencial já configurada nenhum campo aparece focado")
    func noFieldLooksFocusedOnceTheCredentialIsConfigured() async {
        let model = await Setup.opened(store: RecordingCredentialStore(seeded: credentialCanary))

        let reach = reachOffering(model.content)
        #expect(model.stage == .configured)
        #expect(reach.focusedField == nil)
    }

    @Test("sem a condição de janela chave o campo não exibe cursor nem realce de foco")
    func withoutTheKeyWindowConditionTheFieldShowsNoCaret() async {
        let reach = await reachOffering(Setup.opened().content)

        reach.observed(keyWindow: false)

        #expect(reach.focusedField == nil)
    }

    @Test("a aparência volta a refletir o foco real quando a janela volta a receber teclado")
    func theAppearanceFollowsTheRealFocusWhenTheKeyboardComesBack() async {
        let reach = await reachOffering(Setup.opened().content)

        reach.observed(keyWindow: false)
        reach.observed(keyWindow: true)

        #expect(reach.focusedField == .credential)
    }

    @Test("voltar devolve o foco ao campo que o tinha, e não ao que a superfície prefere")
    func returningRestoresTheFieldThatHadTheFocus() async {
        let acquirer = StubAssistedAcquirer(gated: true)
        let model = await Setup.opened(acquirer: acquirer)

        async let assisting: Void = model.assist()
        await Setup.settle(model, until: .assisting)

        let reach = reachOffering(model.content)
        reach.personFocused(.credential)
        reach.observed(keyWindow: false)
        reach.observed(keyWindow: true)

        #expect(reach.focusedField == .credential)

        await acquirer.release()
        await assisting
    }

    @Test("um campo que a superfície não desenha não fica focado")
    func aFieldTheSurfaceDoesNotDrawNeverTakesTheFocus() async {
        let reach = await reachOffering(Setup.opened().content)

        reach.personFocused(.authorizationCode)

        #expect(reach.focusedField == .credential)
    }

    @Test("fechada a superfície, nada continua parecendo focado")
    func nothingKeepsLookingFocusedOnceTheSurfaceCloses() async {
        let reach = await reachOffering(Setup.opened().content)

        reach.surfaceClosed()

        #expect(reach.focusedField == nil)
    }

    @Test("o pedido do aplicativo de vir à frente não faz nenhum campo declarar que recebe digitação")
    func theApplicationsOwnRequestToComeForwardDeclaresNothing() async {
        let requests = ForegroundRequests()
        let reach = KeyboardReach(application: requests)
        await reach.offers(Setup.opened().content.focusableFields)

        reach.requestForeground()

        #expect(requests.count == 1)
        #expect(reach.focusedField == nil)
    }
}

private enum AppSources {
    enum Unreadable: Error {
        case noSourcesFound
    }

    static func all() throws -> [URL] {
        let directory = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources")
        let contents = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        let sources = (contents?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }

        guard !sources.isEmpty else { throw Unreadable.noSourcesFound }
        return sources
    }

    static func containing(_ fragment: String) throws -> [String] {
        try all()
            .filter { try String(contentsOf: $0, encoding: .utf8).contains(fragment) }
            .map(\.lastPathComponent)
    }
}

@Suite("Fatos de plataforma que não falham em compilação")
struct SilentPlatformFailureTests {
    @Test("pedir para vir à frente tem um lugar só no aplicativo")
    func askingToComeForwardHasASinglePlaceInTheApplication() throws {
        #expect(try AppSources.containing("NSApp.activate") == ["KeyboardReach.swift"])
        #expect(try AppSources.containing("activate(ignoringOtherApps").isEmpty)
    }

    @Test("nenhuma superfície é obtida por tomar a condição de janela chave à força")
    func noSurfaceGrabsTheKeyWindowCondition() throws {
        #expect(try AppSources.containing("makeKey").isEmpty)
        #expect(try AppSources.containing("orderFront").isEmpty)
    }

    @Test("nenhuma janela ou painel do aplicativo é construído à mão")
    func noWindowOrPanelIsBuiltByHand() throws {
        for construction in ["NSPanel(", "NSWindow(", "NSHostingView(", "NSStatusItem("] {
            #expect(try AppSources.containing(construction).isEmpty, "\(construction) construído à mão")
        }
    }

    @Test("o menu principal é o que o sistema monta, e o aplicativo não o instala nem o inspeciona")
    func theMainMenuIsTheOneTheSystemBuilds() throws {
        #expect(try AppSources.containing("mainMenu").isEmpty)
        #expect(try AppSources.containing("NSMenu(").isEmpty)
    }
}
