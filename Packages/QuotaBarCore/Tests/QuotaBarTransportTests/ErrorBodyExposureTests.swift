import Foundation
import QuotaBarCore
import Testing

@testable import QuotaBarTransport

@Suite("Não retenção do corpo de erro no estado publicado")
struct ErrorBodyExposureTests {
    private static let canary = "CORPO-DE-ERRO-NAO-DEVE-SER-PUBLICADO"

    private static let refusals: [ProbeHTTPResponse] = [400, 401, 403, 404, 429, 500, 529].map(carrying(status:))

    private static let throttling = carrying(status: 429)

    private static func carrying(status: Int) -> ProbeHTTPResponse {
        ProbeHTTPResponse(
            status: status,
            headers: ["retry-after": "30"],
            body: Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"\#(canary)"}}"#.utf8)
        )
    }

    @Test("o corpo de erro não chega ao estado publicado", arguments: refusals)
    func noPublishedStateCarriesTheErrorBody(response: ProbeHTTPResponse) async {
        let harness = ProviderHarness(responses: [response])
        #expect(await harness.waitForState { if case .failed = $0.lastAttempt { true } else { false } })

        #expect(!harness.published.isEmpty, "nenhum estado publicado para varrer")

        for state in harness.published {
            #expect(!String(describing: state).contains(Self.canary), "vazou no estado de \(response.status)")
            #expect(!String(reflecting: state).contains(Self.canary), "vazou ao refletir o estado de \(response.status)")
        }
    }

    @Test("a leitura seguinte ao estrangulamento não ressuscita o corpo de erro")
    func aReadingAfterAThrottlingCarriesNoErrorBody() async {
        let harness = ProviderHarness(responses: [Self.throttling, CannedResponse.reading()])
        #expect(await harness.waitForState { $0.lastAttempt == .failed(.communicationFailure) })

        harness.clock.advance(by: 900)
        #expect(await harness.waitForReading(sequence: 1))
        #expect(harness.latest?.snapshot != nil, "a segunda resposta deveria ter virado leitura")

        for state in harness.published {
            #expect(!String(describing: state).contains(Self.canary))
            #expect(!String(reflecting: state).contains(Self.canary))
        }
    }
}
