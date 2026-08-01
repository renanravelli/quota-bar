import Foundation
import Testing

@testable import QuotaBarCore

private func decimal(_ literal: String) -> Decimal {
    guard let value = Decimal(string: literal) else {
        fatalError("literal decimal inválido no teste: \(literal)")
    }
    return value
}

@Suite("Utilization — ponto fixo em basis points")
struct UtilizationTests {
    @Test("AC-3: 78,9% consumidos truncam para 78")
    func truncatesDownToWholePercent() {
        let utilization = Utilization(originPercent: decimal("78.9"))

        #expect(utilization?.basisPoints == 7890)
        #expect(utilization?.truncatedPercent == 78)
    }

    @Test("AC-3: fração da sonda é convertida sem ponto flutuante")
    func acceptsOriginFraction() {
        let utilization = Utilization(originFraction: "0.789")

        #expect(utilization?.basisPoints == 7890)
        #expect(utilization?.truncatedPercent == 78)
    }

    @Test("AC-3: percentual com uma casa da status line preserva a casa decimal")
    func acceptsOriginPercentWithOneDecimalPlace() {
        let utilization = Utilization(originPercent: decimal("23.5"))

        #expect(utilization?.basisPoints == 2350)
        #expect(utilization?.truncatedPercent == 23)
    }

    @Test("AC-4: percentual negativo não é representável")
    func rejectsNegativeValues() {
        #expect(Utilization(originPercent: decimal("-0.1")) == nil)
        #expect(Utilization(originFraction: "-0.42") == nil)
        #expect(Utilization(basisPoints: -1) == nil)
    }

    @Test("AC-4: fração ilegível não produz valor")
    func rejectsUnparsableFraction() {
        #expect(Utilization(originFraction: "") == nil)
        #expect(Utilization(originFraction: "indisponível") == nil)
    }

    @Test("AC-33: 50,4% e 50,6% são distintos e ambos truncam para 50")
    func comparesBeforeTruncation() {
        let fiveHour = Utilization(originPercent: decimal("50.4"))
        let sevenDay = Utilization(originPercent: decimal("50.6"))

        #expect(fiveHour != sevenDay)
        #expect(fiveHour! < sevenDay!)
        #expect(fiveHour?.truncatedPercent == 50)
        #expect(sevenDay?.truncatedPercent == 50)
    }

    @Test("AC-33: igualdade exata é igualdade inteira, sem erro de arredondamento")
    func exactEqualityIsIntegerEquality() {
        let fiveHour = Utilization(originPercent: decimal("50.0"))
        let sevenDay = Utilization(originFraction: "0.50")

        #expect(fiveHour == sevenDay)
        #expect(!(fiveHour! < sevenDay!))
        #expect(!(sevenDay! < fiveHour!))
    }

    @Test("AC-15: 100% consumidos atingem o limite")
    func reachesLimitAtOneHundredPercent() {
        let utilization = Utilization(originPercent: decimal("100"))

        #expect(utilization?.basisPoints == 10_000)
        #expect(utilization?.truncatedPercent == 100)
        #expect(utilization?.isAtOrAboveLimit == true)
    }

    @Test("AC-16: 118% é representável e não é resposta inesperada")
    func keepsOverageRepresentable() {
        let utilization = Utilization(originPercent: decimal("118"))

        #expect(utilization?.basisPoints == 11_800)
        #expect(utilization?.truncatedPercent == 118)
        #expect(utilization?.isAtOrAboveLimit == true)
    }

    @Test("AC-15: 99,99% ainda não atingiu o limite")
    func staysBelowLimitJustUnderOneHundred() {
        let utilization = Utilization(originPercent: decimal("99.99"))

        #expect(utilization?.basisPoints == 9_999)
        #expect(utilization?.truncatedPercent == 99)
        #expect(utilization?.isAtOrAboveLimit == false)
    }

    @Test("AC-3: zero é valor válido e distinto de ausência")
    func acceptsZero() {
        let utilization = Utilization(originPercent: .zero)

        #expect(utilization?.basisPoints == 0)
        #expect(utilization?.truncatedPercent == 0)
        #expect(utilization?.isAtOrAboveLimit == false)
    }

    @Test("AC-3: precisão abaixo do basis point é truncada, não arredondada")
    func truncatesBelowBasisPointPrecision() {
        #expect(Utilization(originPercent: decimal("78.999"))?.basisPoints == 7899)
        #expect(Utilization(originFraction: "0.789999")?.basisPoints == 7899)
    }
}
