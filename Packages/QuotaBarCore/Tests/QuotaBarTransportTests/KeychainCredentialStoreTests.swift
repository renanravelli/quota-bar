import Foundation
import Security
import Testing

@testable import QuotaBarTransport

extension KeychainOutcome {
    var value: T? {
        guard case .success(let value) = self else { return nil }
        return value
    }

    var failure: KeychainFailure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }

    var succeeded: Bool {
        guard case .success = self else { return false }
        return true
    }
}

private struct Fixture {
    let keychain = InMemoryKeychain()
    let store: KeychainCredentialStore

    init() {
        store = KeychainCredentialStore(keychain: keychain)
    }

    var token: SubscriptionToken {
        SubscriptionToken(pasted: canary)!
    }

    var replacement: SubscriptionToken {
        SubscriptionToken(pasted: "sk-ant-oat01-SEGUNDO-VALOR")!
    }
}

@Suite("Ciclo de vida da credencial no Keychain")
struct KeychainCredentialStoreTests {
    @Test("REQ-13: gravar guarda o valor e a presença passa a ser afirmada")
    func storingMakesTheCredentialPresent() async {
        let fixture = Fixture()

        #expect(await fixture.store.isConfigured().value == false)
        #expect(await fixture.store.store(fixture.token).succeeded)
        #expect(await fixture.store.isConfigured().value == true)
        #expect(await fixture.store.load().value?.withValue { $0 } == canary)
    }

    @Test("REQ-13: a credencial é gravada com acesso apenas com a máquina desbloqueada e sem sincronização")
    func storedItemHonoursTheDeclaredAccessibility() async throws {
        let fixture = Fixture()
        _ = await fixture.store.store(fixture.token)

        let add = try #require(fixture.keychain.calls.first { $0.operation == .add })

        #expect(add.attributes[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(add.attributes[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleWhenUnlocked as String)
        #expect(add.attributes[kSecAttrSynchronizable as String] as? Bool == false)
    }

    @Test("REQ-11: gravar sobre uma credencial existente substitui o valor, sem duplicar o item")
    func storingOverAnExistingCredentialReplacesIt() async {
        let fixture = Fixture()
        _ = await fixture.store.store(fixture.token)

        #expect(await fixture.store.store(fixture.replacement).succeeded)
        #expect(fixture.keychain.storedItemCount == 1)
        #expect(await fixture.store.load().value?.withValue { $0 } == "sk-ant-oat01-SEGUNDO-VALOR")
    }

    @Test("AC-18: substituição malsucedida preserva a credencial anterior")
    func failedReplacementPreservesThePreviousCredential() async {
        let fixture = Fixture()
        _ = await fixture.store.store(fixture.token)

        fixture.keychain.failAllOperations(with: errSecAuthFailed)
        #expect(await fixture.store.store(fixture.replacement).failure == .authorizationDenied)

        fixture.keychain.stopFailing()
        #expect(await fixture.store.isConfigured().value == true)
        #expect(await fixture.store.load().value?.withValue { $0 } == canary)
    }

    @Test("AC-19: remover apaga o item, e nenhuma leitura posterior devolve o valor")
    func removalDeletesTheItem() async {
        let fixture = Fixture()
        _ = await fixture.store.store(fixture.token)

        #expect(await fixture.store.remove().succeeded)
        #expect(fixture.keychain.storedItemCount == 0)
        #expect(await fixture.store.isConfigured().value == false)
        #expect(await fixture.store.load().failure == .itemNotFound)
    }

    @Test("REQ-12: remover o que não existe é declarado como item ausente, não como remoção feita")
    func removingWhatIsNotThereReportsItemNotFound() async {
        let fixture = Fixture()

        #expect(await fixture.store.remove().failure == .itemNotFound)
    }

    @Test("Contratos §3: saber se há credencial não traz o segredo para a memória")
    func checkingPresenceNeverRequestsTheValue() async throws {
        let fixture = Fixture()
        _ = await fixture.store.store(fixture.token)
        _ = await fixture.store.isConfigured()

        #expect(!fixture.keychain.calls.contains { $0.operation == .copyData })

        let existence = try #require(fixture.keychain.calls.last { $0.operation == .matchExists })
        #expect(existence.attributes[kSecReturnData as String] == nil)
    }

    @Test("REQ-15: cada estado do Keychain vira uma falha própria, distinta de credencial inválida", arguments: [
        (errSecInteractionNotAllowed, KeychainFailure.interactionNotAllowed),
        (errSecAuthFailed, .authorizationDenied),
        (errSecUserCanceled, .authorizationDenied),
        (errSecNotAvailable, .unexpected(errSecNotAvailable)),
        (errSecParam, .unexpected(errSecParam))
    ])
    func keychainStatusesMapToTheirOwnFailure(status: OSStatus, expected: KeychainFailure) async {
        let fixture = Fixture()
        fixture.keychain.failAllOperations(with: status)

        #expect(await fixture.store.store(fixture.token).failure == expected)
        #expect(await fixture.store.load().failure == expected)
        #expect(await fixture.store.remove().failure == expected)
        #expect(await fixture.store.isConfigured().failure == expected)
    }

    @Test("Erros: credencial guardada que não se deixa ler é ilegível, não ausente nem recusada", arguments: [
        Data([0xFF, 0xFE, 0xFD]),
        Data(),
        Data("sk-ant-api03-outro-produto".utf8)
    ])
    func unreadableStoredDataIsReportedAsSuch(planted: Data) async {
        let fixture = Fixture()
        fixture.keychain.plant(planted, service: KeychainCredentialStore.service, account: KeychainCredentialStore.account)

        #expect(await fixture.store.load().failure == .unexpected(errSecDecode))
        #expect(await fixture.store.isConfigured().value == true)
    }

    @Test("AC-23: nenhum campo da falha de Keychain carrega o valor")
    func keychainFailureNeverCarriesTheValue() async {
        let fixture = Fixture()
        _ = await fixture.store.store(fixture.token)

        for status in [errSecAuthFailed, errSecInteractionNotAllowed, errSecItemNotFound, errSecNotAvailable] {
            fixture.keychain.failAllOperations(with: status)

            for outcome in await [
                String(reflecting: fixture.store.store(fixture.token)),
                String(reflecting: fixture.store.load()),
                String(reflecting: fixture.store.remove()),
                String(reflecting: fixture.store.isConfigured())
            ] {
                #expect(!outcome.contains(canary), "vazou em: \(outcome)")
            }
        }
    }

    @Test("REQ-13 e REQ-14: o valor só atravessa como dado do item, nunca como atributo de consulta")
    func theValueOnlyTravelsAsTheItemData() async {
        let fixture = Fixture()
        _ = await fixture.store.store(fixture.token)
        _ = await fixture.store.load()
        _ = await fixture.store.isConfigured()
        _ = await fixture.store.remove()

        for call in fixture.keychain.calls {
            for (key, attribute) in call.attributes where key != kSecValueData as String {
                #expect(!String(describing: attribute).contains(canary), "vazou em \(key)")
            }
        }

        #expect(fixture.keychain.calls.contains { $0.attributes[kSecValueData as String] as? Data == Data(canary.utf8) })
    }
}
