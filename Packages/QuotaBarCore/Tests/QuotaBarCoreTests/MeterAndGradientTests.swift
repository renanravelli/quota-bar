import Foundation
import Testing

@testable import QuotaBarCore

private func utilization(_ percent: String) -> Utilization {
    Utilization(originPercent: Decimal(string: percent)!)!
}

@Suite("Medidor de segmentos")
struct MeterTests {
    @Test(
        "AC-14: segmentos acesos por percentual",
        arguments: [
            (percent: "0", lit: 0),
            (percent: "0.1", lit: 1),
            (percent: "5", lit: 1),
            (percent: "5.1", lit: 2),
            (percent: "50", lit: 10),
            (percent: "78.9", lit: 16),
            (percent: "100", lit: 20)
        ]
    )
    func litSegmentsForPercent(percent: String, lit: Int) {
        #expect(Meter.litSegments(for: utilization(percent)) == lit)
    }

    @Test("AC-14: em 78,9% o medidor acende 16 e o número continua exibindo 78")
    func meterRoundsUpWhileTheNumberTruncates() {
        let value = utilization("78.9")

        #expect(Meter.litSegments(for: value) == 16)
        #expect(value.displayablePercent == 78)
    }

    @Test("AC-14: qualquer consumo maior que zero acende ao menos um segmento")
    func anyConsumptionLightsAtLeastOneSegment() {
        #expect(Meter.litSegments(for: Utilization(basisPoints: 0)!) == 0)
        #expect(Meter.litSegments(for: Utilization(basisPoints: 1)!) == 1)
        #expect(Meter.litSegments(for: utilization("0.01")) == 1)
        #expect(Meter.litSegments(for: utilization("4.99")) == 1)
    }

    @Test("AC-14: o medidor nunca passa de vinte segmentos, mesmo com overage")
    func meterIsCappedAtTwentySegments() {
        #expect(Meter.segmentCount == 20)
        #expect(Meter.litSegments(for: utilization("100")) == 20)
        #expect(Meter.litSegments(for: utilization("118")) == 20)
        #expect(Meter.litSegments(for: utilization("250")) == 20)
    }

    @Test("AC-14: o medidor é monotônico e cobre todos os degraus")
    func meterIsMonotonicAcrossTheRange() {
        var previous = 0

        for basisPoints in stride(from: 0, through: 10_000, by: 1) {
            let lit = Meter.litSegments(for: Utilization(basisPoints: basisPoints)!)
            #expect(lit >= previous)
            #expect(lit <= Meter.segmentCount)
            previous = lit
        }

        #expect(previous == 20)
    }
}

@Suite("Gradiente de consumo")
struct ConsumptionGradientTests {
    @Test("AC-15: a cor coincide com as três âncoras")
    func gradientMatchesItsAnchors() {
        #expect(ConsumptionGradient.color(for: utilization("0")) == Palette.ok)
        #expect(ConsumptionGradient.color(for: utilization("75")) == Palette.warning)
        #expect(ConsumptionGradient.color(for: utilization("100")) == Palette.bad)
    }

    @Test("AC-15: consumo acima de 100% permanece na âncora ruim")
    func overageStaysAtTheBadAnchor() {
        #expect(ConsumptionGradient.color(for: utilization("118")) == Palette.bad)
    }

    @Test("AC-15: a cor interpola entre as âncoras nos valores intermediários")
    func gradientInterpolatesBetweenAnchors() {
        let midway = ConsumptionGradient.color(for: utilization("37.5"))

        #expect(midway != Palette.ok)
        #expect(midway != Palette.warning)
        #expect(abs(midway.red - (Palette.ok.red + Palette.warning.red) / 2) < 0.0001)
        #expect(abs(midway.green - (Palette.ok.green + Palette.warning.green) / 2) < 0.0001)
        #expect(abs(midway.blue - (Palette.ok.blue + Palette.warning.blue) / 2) < 0.0001)
    }

    @Test("AC-15: não há descontinuidade nas fronteiras de faixa 74/75 e 89/90")
    func gradientHasNoJumpAtBandBoundaries() {
        for boundary in [7_400, 8_900] {
            let stepAtBoundary = step(from: boundary, to: boundary + 100)
            let stepBefore = step(from: boundary - 100, to: boundary)

            #expect(
                abs(stepAtBoundary - stepBefore) < 0.0001,
                "a fronteira de \(boundary / 100)% tem passo \(stepAtBoundary) contra \(stepBefore) do vizinho"
            )
        }
    }

    @Test("AC-15: a única junção entre trechos, em 75%, não produz salto")
    func theJunctionBetweenSegmentsIsSmooth() {
        let justBelow = step(from: 7_499, to: 7_500)
        let justAbove = step(from: 7_500, to: 7_501)

        #expect(justBelow < 0.001)
        #expect(justAbove < 0.001)
        #expect(ConsumptionGradient.color(for: Utilization(basisPoints: 7_500)!) == Palette.warning)
    }

    private func step(from: Int, to: Int) -> Double {
        distance(
            ConsumptionGradient.color(for: Utilization(basisPoints: from)!),
            ConsumptionGradient.color(for: Utilization(basisPoints: to)!)
        )
    }

    @Test("AC-15: a curva é contínua em todo o intervalo, inclusive na âncora de 75%")
    func gradientIsContinuousAcrossTheWholeRange() {
        var largestStep = 0.0
        var previous = ConsumptionGradient.color(for: Utilization(basisPoints: 0)!)

        for basisPoints in stride(from: 1, through: 10_000, by: 1) {
            let current = ConsumptionGradient.color(for: Utilization(basisPoints: basisPoints)!)
            largestStep = max(largestStep, distance(previous, current))
            previous = current
        }

        #expect(largestStep < 0.005, "maior salto entre passos de 0,01 ponto: \(largestStep)")
    }

    private func distance(_ a: RGBColor, _ b: RGBColor) -> Double {
        abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue)
    }
}
