import AppKit
import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

private final class MascotBundleMarker {}

@Suite("Mascote com ausência graciosa")
struct MascotAbsenceTests {
    private static let bundleWithoutArt = Bundle(for: MascotBundleMarker.self)

    private static let expressions: [MascotExpression] = [
        .normal, .attention, .critical, .exhausted, .noValue
    ]

    @Test("QB-APP-002 AC-19: há uma arte de mascote para cada uma das cinco expressões")
    func everyExpressionHasItsOwnArt() {
        for expression in Self.expressions {
            #expect(MascotAsset.image(for: expression) != nil, "sem arte de mascote para \(expression)")
        }
        #expect(Set(Self.expressions.map(MascotAsset.imageName)).count == 5)
    }

    @Test("QB-APP-002 AC-33: com a arte indisponível no bundle, nenhuma imagem é carregada e não há reserva")
    func absentArtLoadsNoImageAndHasNoFallback() {
        for expression in Self.expressions {
            #expect(MascotAsset.image(for: expression, in: Self.bundleWithoutArt) == nil)
        }
    }

    @Test("QB-APP-002 AC-33: o painel continua com todas as suas informações sem o mascote")
    func panelKeepsEveryInformationWithoutTheMascot() {
        let snapshot = QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: Utilization(originPercent: 78)!,
                resetsAt: Date(timeIntervalSince1970: 1_700_003_600),
                status: .allowed
            ),
            sevenDay: WindowReading(
                utilization: Utilization(originPercent: 41)!,
                resetsAt: Date(timeIntervalSince1970: 1_700_086_400),
                status: .allowed
            ),
            overallStatus: .allowed,
            nextResetAt: nil,
            bindingWindow: .window(.fiveHour),
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: 1,
            readAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .primaryProbe
        )!
        let state = QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .succeeded(at: Date(timeIntervalSince1970: 1_700_000_000)),
            cycle: TestCycle.scheduled(),
            maxIdleCadenceSinceReading: .seconds(180),
            source: .primaryProbe
        )

        var latch = StaleLatch()
        var deferral = DeferralLatch()
        let now = Date(timeIntervalSince1970: 1_700_000_180)
        let indicator = IndicatorStateResolver.resolve(state: state, latch: &latch, now: now)
        let content = PanelContentBuilder.build(
            state: state, indicator: indicator, at: now, deferralLatch: &deferral
        )

        #expect(content.fiveHour.utilization == "78%")
        #expect(content.sevenDay.utilization == "41%")
        #expect(content.fiveHour.reset != nil)
        #expect(content.selection != nil)
        #expect(content.cadenceLine != nil)
        #expect(content.source != nil)
        #expect(!content.quitTitle.isEmpty)
    }

    @Test("QB-APP-002 AC-19: a expressão acompanha a faixa mesmo sem arte para desenhá-la")
    func expressionIsResolvedEvenWithoutArt() {
        let utilization = Utilization(originPercent: 95)!
        let value = DisplayValue(
            selection: .reportedByOrigin(.fiveHour),
            utilization: utilization,
            band: ConsumptionBand(utilization: utilization)
        )

        #expect(MascotResolver.expression(for: .ready(value)) == .critical)
        #expect(MascotAsset.imageName(for: .critical) == "MascotCritical")
    }
}
