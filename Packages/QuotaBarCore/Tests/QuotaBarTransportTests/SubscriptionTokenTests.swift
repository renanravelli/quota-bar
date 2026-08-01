import Foundation
import Testing

@testable import QuotaBarTransport

let canary = "sk-ant-oat01-CANARIO-CREDENCIAL-NAO-DEVE-VAZAR"

@Suite("Forma e redação do portador da credencial")
struct SubscriptionTokenTests {
    @Test("AC-7: valor com prefixo diferente do esperado é recusado", arguments: [
        "sk-ant-api03-abcdefghijklmnopqrstuvwxyz",
        "sk-ant-oat02-abcdefghijklmnopqrstuvwxyz",
        "oat01-abcdefghijklmnopqrstuvwxyz",
        "SK-ANT-OAT01-abcdefghijklmnopqrstuvwxyz"
    ])
    func rejectsValuesWithoutTheExpectedPrefix(pasted: String) {
        #expect(SubscriptionToken(pasted: pasted) == nil)
    }

    @Test("AC-7: valor com espaço interno é recusado, mesmo com o prefixo esperado", arguments: [
        "sk-ant-oat01-abcdef ghijkl",
        "sk-ant-oat01-abcdef\tghijkl",
        "sk-ant-oat01-abcdef\nghijkl",
        "sk-ant-oat01-abcdef\r\nghijkl",
        "sk-ant-oat01- abcdefghijkl",
        "sk-ant-oat01-abcdefghijkl mnopqr stuvwx"
    ])
    func rejectsValuesWithInteriorWhitespace(pasted: String) {
        #expect(SubscriptionToken(pasted: pasted) == nil)
    }

    @Test("AC-7: aparar as bordas não resgata um valor com espaço interno")
    func trimmingDoesNotRescueInteriorWhitespace() {
        #expect(SubscriptionToken(pasted: "  \n sk-ant-oat01-abcdef ghijkl \n  ") == nil)
    }

    @Test("AC-8: bordas em branco não custam uma tentativa ao usuário", arguments: [
        "  \n\t\(canary)\n  ",
        "\(canary)\n",
        " \(canary)",
        "\r\n\(canary)\r\n"
    ])
    func trimsSurroundingWhitespace(pasted: String) throws {
        let token = try #require(SubscriptionToken(pasted: pasted))

        #expect(token.withValue { $0 } == canary)
    }

    @Test("AC-9: campo vazio é recusado", arguments: ["", "   ", "\n\t "])
    func rejectsEmptyInput(pasted: String) {
        #expect(SubscriptionToken(pasted: pasted) == nil)
    }

    @Test("AC-24: interpolar o portador não produz o valor")
    func interpolationDoesNotProduceTheValue() throws {
        let token = try #require(SubscriptionToken(pasted: canary))

        #expect(!"credencial: \(token)".contains(canary))
        #expect("credencial: \(token)" == "credencial: SubscriptionToken(redigido)")
    }

    @Test("AC-24: descrever e depurar o portador não produz o valor")
    func descriptionAndDebugDescriptionAreRedacted() throws {
        let token = try #require(SubscriptionToken(pasted: canary))

        var dumped = ""
        dump(token, to: &dumped)

        for rendering in [
            token.description,
            token.debugDescription,
            String(describing: token),
            String(reflecting: token),
            dumped
        ] {
            #expect(!rendering.contains(canary), "vazou em: \(rendering)")
        }
    }

    @Test("AC-24: o portador dentro de outro valor continua redigido")
    func redactionSurvivesBeingNested() throws {
        let token = try #require(SubscriptionToken(pasted: canary))
        let outcome = KeychainOutcome.success(token)

        #expect(!String(describing: outcome).contains(canary))
        #expect(!String(describing: [token]).contains(canary))
        #expect(!String(describing: Optional(token)).contains(canary))
    }

    @Test("REQ-13: o portador não é serializável, para que não haja segundo caminho de saída")
    func theTokenIsNotEncodable() throws {
        let token: Any = try #require(SubscriptionToken(pasted: canary))

        #expect(!(token is any Encodable))
        #expect(!(token is any Decodable))
    }

    @Test("REQ-17: o valor é entregue ao escopo, e é o valor colado")
    func withValueDeliversThePastedValue() throws {
        let token = try #require(SubscriptionToken(pasted: canary))

        #expect(token.withValue { $0.count } == canary.count)
        #expect(token.withValue { Data($0.utf8) } == Data(canary.utf8))
    }

    @Test("REQ-17: withValue propaga o erro lançado pelo escopo")
    func withValueRethrows() throws {
        struct Interrupted: Error {}
        let token = try #require(SubscriptionToken(pasted: canary))

        #expect(throws: Interrupted.self) {
            try token.withValue { _ in throw Interrupted() }
        }
    }
}
