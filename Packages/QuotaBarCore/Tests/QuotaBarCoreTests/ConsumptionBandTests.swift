import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Faixas de consumo")
struct ConsumptionBandTests {
    private static func band(_ percent: String) -> ConsumptionBand? {
        guard let utilization = TestSnapshot.utilization(percent) else { return nil }
        return ConsumptionBand(utilization: utilization)
    }

    @Test("fronteira da faixa de atenção em 74 e 75")
    func attentionBoundary() {
        #expect(Self.band("74") == .normal)
        #expect(Self.band("75") == .attention)
    }

    @Test("fronteira da faixa crítica em 89 e 90")
    func criticalBoundary() {
        #expect(Self.band("89") == .attention)
        #expect(Self.band("90") == .critical)
    }

    @Test("fronteira de esgotado em 99 e 100")
    func exhaustedBoundary() {
        #expect(Self.band("99") == .critical)
        #expect(Self.band("100") == .exhausted)
    }

    @Test("a faixa acompanha o percentual exibido, que é truncado")
    func bandFollowsTruncatedPercent() {
        #expect(Self.band("74.9") == .normal)
        #expect(Self.band("75.0") == .attention)
        #expect(Self.band("89.99") == .attention)
        #expect(Self.band("99.9") == .critical)
    }

    @Test("a faixa normal cobre de zero até 74")
    func normalBandCoversLowerRange() {
        #expect(Self.band("0") == .normal)
        #expect(Self.band("50") == .normal)
        #expect(Self.band("73") == .normal)
    }

    @Test("consumo acima de 100 permanece esgotado")
    func overageStaysExhausted() {
        #expect(Self.band("118") == .exhausted)
        #expect(Self.band("250") == .exhausted)
    }

    @Test("as quatro faixas são distintas entre si")
    func fourDistinctBands() {
        let bands: Set<ConsumptionBand?> = [
            Self.band("50"),
            Self.band("80"),
            Self.band("95"),
            Self.band("100")
        ]

        #expect(bands.count == 4)
    }
}
