import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

@MainActor
@Suite("Motivo do botão indisponível")
struct ButtonAvailabilityTests {
    private struct Surface {
        let label: String
        let availabilities: [ActionAvailability]
    }

    private static func everySurface() async -> [Surface] {
        var surfaces: [Surface] = []

        func gather(_ label: String, _ model: CredentialSetupModel) {
            surfaces.append(Surface(
                label: label,
                availabilities: [
                    model.content.saveAvailability,
                    model.submitAvailability(codeTyped: false),
                    model.submitAvailability(codeTyped: true)
                ]
            ))
        }

        gather("sem credencial guardada", await Setup.opened())
        gather("sem o Claude Code", await Setup.opened(discovery: .notFound))
        gather("com credencial guardada", await Setup.opened(store: RecordingCredentialStore(seeded: credentialCanary)))

        let refusing = await Setup.opened(verifier: GatedVerifier(.credentialRejected))
        await refusing.save(credentialCanary)
        gather("com a credencial recusada", refusing)

        let acquirer = StubAssistedAcquirer(gated: true)
        let assisting = await Setup.opened(acquirer: acquirer)
        async let conduction: Void = assisting.assist()
        await Setup.settle(assisting, until: .assisting)
        gather("durante a espera assistida", assisting)
        await acquirer.release()
        await conduction

        return surfaces
    }

    @Test("durante a espera assistida salvar fica indisponível, e o motivo vem do modelo em texto")
    func savingIsUnavailableWhileTheAssistedWayRunsAndTheModelSaysWhy() async {
        let acquirer = StubAssistedAcquirer(gated: true)
        let model = await Setup.opened(acquirer: acquirer)

        async let conduction: Void = model.assist()
        await Setup.settle(model, until: .assisting)

        let reason = model.content.saveAvailability.reason
        #expect(model.content.saveAvailability != .available)
        #expect(reason?.isEmpty == false)
        #expect(reason == CredentialSetupText.saveBusyWithAssistance)

        await acquirer.release()
        await conduction
    }

    @Test("sem o Claude Code salvar fica indisponível, e o motivo vem do modelo em texto")
    func savingIsUnavailableWithoutClaudeCodeAndTheModelSaysWhy() async {
        let model = await Setup.opened(discovery: .notFound)

        #expect(model.content.saveAvailability != .available)
        #expect(model.content.saveAvailability.reason == CredentialSetupText.saveNeedsClaudeCode)
    }

    @Test("sem código colado enviar fica indisponível, e o motivo vem do modelo em texto")
    func submittingIsUnavailableWithoutACodeAndTheModelSaysWhy() async {
        let model = await Setup.opened()

        #expect(model.submitAvailability(codeTyped: false) != .available)
        #expect(model.submitAvailability(codeTyped: false).reason == CredentialSetupText.submitNeedsCode)
    }

    @Test("com o código colado enviar fica disponível")
    func submittingBecomesAvailableOnceTheCodeIsThere() async {
        let model = await Setup.opened()

        #expect(model.submitAvailability(codeTyped: true) == .available)
    }

    @Test("nenhuma indisponibilidade da superfície de credencial fica sem motivo dito em texto")
    func noUnavailabilityOnTheCredentialSurfaceIsLeftWithoutAReason() async {
        let surfaces = await Self.everySurface()
        var unavailable = 0
        var examined = 0

        for surface in surfaces {
            for availability in surface.availabilities {
                examined += 1
                guard case let .unavailable(reason) = availability else { continue }

                unavailable += 1
                #expect(
                    reason.trimmingCharacters(in: .whitespacesAndNewlines).count > 10,
                    "botão inerte com motivo vazio ou vago em \(surface.label): '\(reason)'"
                )
            }
        }

        #expect(examined == surfaces.count * 3, "a varredura não leu todos os botões de cada superfície")
        #expect(surfaces.count == 5, "a varredura não alcançou todas as superfícies previstas")
        #expect(unavailable > 0, "nenhum caso de indisponibilidade foi exercitado")
    }

    @Test("nenhuma tela decide por conta própria se um botão está disponível")
    func noScreenDecidesAvailabilityOnItsOwn() throws {
        let screens = AppLayout.viewSources.filter { $0.lastPathComponent != "ActionButton.swift" }
        #expect(!screens.isEmpty, "nenhuma tela encontrada para inspecionar")

        for screen in screens {
            let text = try AppLayout.text(of: screen)
            #expect(
                !text.contains(".disabled("),
                "\(screen.lastPathComponent) decide a disponibilidade de um botão fora do modelo"
            )
        }

        let button = try #require(AppLayout.viewSources.first { $0.lastPathComponent == "ActionButton.swift" })
        #expect(try AppLayout.text(of: button).contains(".disabled(availability != .available)"))
    }

    @Test("o motivo que o modelo declara é o texto que a tela desenha")
    func theReasonTheModelDeclaresIsTheTextTheScreenDraws() throws {
        let screen = try #require(AppLayout.viewSources.first { $0.lastPathComponent == "CredentialSetupView.swift" })
        let text = try AppLayout.text(of: screen)

        #expect(text.contains("content.saveAvailability.reason"))
        #expect(text.contains("submit.reason"))
    }
}
