import QuotaBarCore
import SwiftUI
import Testing

@testable import QuotaBar

@MainActor
@Suite("Pictograma desenhado")
struct RenderedPictogramTests {
    private static let minimumPictogramRatio = 3.0

    private func renderedHeight(of view: some View, in metric: RenderedProbe.Environment) throws -> Int {
        try #require(RenderedProbe.raster(view, in: metric), "o instrumento não produziu bitmap").heightInPixels
    }

    @Test("o pictograma cresce ao menos tanto quanto o texto quando a métrica de fonte cresce")
    func thePictogramGrowsAtLeastAsMuchAsTheTextBeside() throws {
        var measured = 0

        for action in ButtonAction.allCases {
            let text = Text(ApprovedButtonTable.title(of: action))
            let smallerText = try renderedHeight(of: text, in: .smallerMetric)
            let largerText = try renderedHeight(of: text, in: .largerMetric)

            try #require(
                largerText > smallerText,
                """
                falha de instrumento: a métrica de fonte injetada não moveu a altura do texto de referência \
                de \(smallerText) px, e sem isso nada se pode afirmar sobre o desenho ao lado dele
                """
            )

            let pictogram = Image(systemName: action.symbolName).imageScale(.large)
            let smallerPictogram = try renderedHeight(of: pictogram, in: .smallerMetric)
            let largerPictogram = try renderedHeight(of: pictogram, in: .largerMetric)

            #expect(
                largerPictogram * smallerText >= smallerPictogram * largerText,
                """
                \(action.symbolName) encolheu ao lado do texto: passou de \(smallerPictogram) para \
                \(largerPictogram) px enquanto o texto foi de \(smallerText) para \(largerText) px
                """
            )
            measured += 1
        }

        #expect(measured == ApprovedButtonTable.declaredActions, "a varredura não alcançou as ações da tabela")
    }

    @Test("o pictograma desenhado se destaca da superfície em que vive")
    func theDrawnPictogramStandsOutFromItsSurface() throws {
        var measured = 0

        for action in ButtonAction.allCases {
            for surface in [Palette.surface, Palette.background] {
                let drawn = Image(systemName: action.symbolName)
                    .imageScale(.large)
                    .foregroundStyle(Color(action.role.color))
                    .padding(8)
                    .background(Color(surface))
                let raster = try #require(RenderedProbe.raster(drawn, in: .smallerMetric))
                let everything = CGRect(x: 0, y: 0, width: raster.widthInPixels, height: raster.heightInPixels)
                let padding = CGRect(x: 0, y: 0, width: 4, height: 4)

                #expect(
                    raster.contrastRatio(of: everything, against: padding) >= Self.minimumPictogramRatio,
                    "\(action.symbolName) desenhado em \(surface.hexString) não alcança 3:1"
                )
                measured += 1
            }
        }

        #expect(
            measured == ApprovedButtonTable.declaredActions * 2,
            "a varredura não alcançou todos os pares de pictograma e superfície"
        )
    }
}

@MainActor
@Suite("Alvo desenhado dos botões")
struct RenderedButtonTargetTests {
    private static let minimumTargetSide: CGFloat = 24

    @Test("nenhum botão é desenhado menor que o alvo mínimo em nenhuma das duas métricas de fonte")
    func noButtonIsDrawnBelowTheMinimumTarget() {
        var measured = 0

        for action in ButtonAction.allCases {
            for metric in [RenderedProbe.Environment.smallerMetric, .largerMetric] {
                let button = ActionButton(
                    action: action,
                    title: ApprovedButtonTable.title(of: action),
                    availability: .available
                ) {}
                let frame = RenderedProbe.layoutFrame(of: button, in: metric)

                #expect(
                    frame.width >= Self.minimumTargetSide && frame.height >= Self.minimumTargetSide,
                    "\(action) foi desenhado em \(frame.size), abaixo dos 24 × 24 pt exigidos"
                )
                measured += 1
            }
        }

        #expect(measured == ApprovedButtonTable.declaredActions * 2, "a varredura não alcançou as ações da tabela")
    }

    @Test("o alvo mínimo do botão não encolhe quando a métrica de fonte cresce")
    func theMinimumTargetNeverShrinksAsTheFontMetricGrows() {
        var measured = 0

        for action in ButtonAction.allCases {
            let title = ApprovedButtonTable.title(of: action)
            let smaller = RenderedProbe.layoutFrame(
                of: ActionButton(action: action, title: title, availability: .available) {},
                in: .smallerMetric
            )
            let larger = RenderedProbe.layoutFrame(
                of: ActionButton(action: action, title: title, availability: .available) {},
                in: .largerMetric
            )

            #expect(
                larger.height >= smaller.height && larger.width >= smaller.width,
                "\(action) encolheu de \(smaller.size) para \(larger.size) com a métrica maior"
            )
            measured += 1
        }

        #expect(measured == ApprovedButtonTable.declaredActions, "a varredura não alcançou as ações da tabela")
    }
}
