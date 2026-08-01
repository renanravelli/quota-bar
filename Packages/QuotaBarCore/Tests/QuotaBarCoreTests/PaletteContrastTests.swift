import Testing

@testable import QuotaBarCore

@Suite("Paleta e contraste")
struct PaletteContrastTests {
    private static func percent(_ value: Int) -> Utilization {
        Utilization(basisPoints: value * 100)!
    }

    @Test("AC-1: a paleta corresponde exatamente aos valores da spec")
    func paletteMatchesTheSpecifiedValues() {
        #expect(Palette.background.hexString == "#0F0F12")
        #expect(Palette.surface.hexString == "#1A1A20")
        #expect(Palette.surfaceSecondary.hexString == "#24242C")
        #expect(Palette.track.hexString == "#26262E")
        #expect(Palette.grid.hexString == "#232329")
        #expect(Palette.border.hexString == "#30303A")
        #expect(Palette.text.hexString == "#F2F0EC")
        #expect(Palette.textMuted.hexString == "#8C8C98")
        #expect(Palette.structuralWeak.hexString == "#5C5C68")
        #expect(Palette.accent.hexString == "#D97757")
        #expect(Palette.ok.hexString == "#4ADE80")
        #expect(Palette.warning.hexString == "#FBBF24")
        #expect(Palette.bad.hexString == "#F87171")
    }

    @Test("AC-1: as cores estruturais não estão no conjunto de cores de texto")
    func structuralColoursAreNotTextColours() {
        for forbidden in Palette.forbiddenAsTextColor {
            #expect(!Palette.textColors.contains(forbidden), "\(forbidden.hexString) não pode carregar texto")
        }
        #expect(Palette.forbiddenAsTextColor.contains(Palette.structuralWeak))
        #expect(Palette.forbiddenAsTextColor.contains(Palette.track))
    }

    @Test("AC-1: track continua válida como superfície sob texto")
    func trackRemainsValidAsASurface() {
        #expect(Palette.surfaces.contains(Palette.track))
        #expect(Contrast.ratio(Palette.text, Palette.track) >= Contrast.minimumRatio)
        #expect(Contrast.ratio(Palette.textMuted, Palette.track) >= Contrast.minimumRatio)
    }

    @Test("AC-1: as margens de contraste registradas na spec conferem")
    func recordedContrastMarginsHold() {
        #expect(abs(Contrast.ratio(Palette.structuralWeak, Palette.surface) - 2.63) < 0.01)
        #expect(abs(Contrast.ratio(Palette.text, Palette.track) - 13.19) < 0.01)
        #expect(abs(Contrast.ratio(Palette.textMuted, Palette.track) - 4.517) < 0.001)
        #expect(abs(Contrast.ratio(Palette.textMuted, Palette.surfaceSecondary) - 4.63) < 0.01)
    }

    @Test("AC-1: structuralWeak como cor de texto reprovaria, e é por isso que é proibida")
    func structuralWeakWouldFailAsTextColour() {
        #expect(Contrast.ratio(Palette.structuralWeak, Palette.surface) < Contrast.minimumRatio)
    }

    @Test("AC-30: todo par de cor de texto e superfície da paleta alcança 4,5:1")
    func everyTextAndSurfacePairMeetsTheMinimum() {
        for textColor in Palette.textColors {
            for surface in Palette.surfaces {
                let ratio = Contrast.ratio(textColor, surface)
                #expect(
                    ratio >= Contrast.minimumRatio,
                    "\(textColor.hexString) sobre \(surface.hexString) dá \(ratio)"
                )
            }
        }
    }

    @Test("AC-30: o percentual tingido pelo gradiente alcança 4,5:1 em passos de 5 pontos")
    func gradientTintedTextMeetsTheMinimumAcrossItsRange() {
        var worstRatio = Double.greatestFiniteMagnitude
        var worstPercent = 0

        for percent in stride(from: 0, through: 100, by: 5) {
            let tint = ConsumptionGradient.color(for: Self.percent(percent))
            let ratio = Contrast.ratio(tint, Palette.surface)

            #expect(ratio >= Contrast.minimumRatio, "gradiente em \(percent)% dá \(ratio)")
            if ratio < worstRatio {
                worstRatio = ratio
                worstPercent = percent
            }
        }

        #expect(worstPercent == 100)
        #expect(abs(worstRatio - 6.26) < 0.01, "pior ponto do gradiente registrado: \(worstRatio)")
    }

    @Test("AC-30: o pior ponto do contínuo não é interior — varredura fina confirma o extremo")
    func theWorstGradientPointIsAtTheEndOfTheRange() {
        var worstRatio = Double.greatestFiniteMagnitude

        for step in stride(from: 0, through: 10_000, by: 5) {
            let tint = ConsumptionGradient.color(for: Utilization(basisPoints: step)!)
            worstRatio = min(worstRatio, Contrast.ratio(tint, Palette.surface))
        }

        #expect(abs(worstRatio - 6.26) < 0.01)
    }

    @Test("AC-30: a fórmula de contraste é a da WCAG, conferida contra valores conhecidos")
    func contrastFormulaMatchesKnownValues() {
        let white = RGBColor(hex: "#FFFFFF")!
        let black = RGBColor(hex: "#000000")!

        #expect(abs(Contrast.ratio(white, black) - 21.0) < 0.001)
        #expect(abs(Contrast.ratio(white, white) - 1.0) < 0.001)
        #expect(abs(Contrast.relativeLuminance(white) - 1.0) < 0.001)
        #expect(abs(Contrast.relativeLuminance(black)) < 0.001)
    }

    @Test("AC-1: hexadecimal inválido não produz cor")
    func invalidHexIsRejected() {
        #expect(RGBColor(hex: "") == nil)
        #expect(RGBColor(hex: "#FFF") == nil)
        #expect(RGBColor(hex: "#GGGGGG") == nil)
        #expect(RGBColor(hex: "#1A1A2") == nil)
        #expect(RGBColor(hex: "1A1A20") != nil)
    }
}
