import Foundation
import QuotaBarCoreFixtures
import Testing

@testable import QuotaBarCore

@Suite("Mapeamento dos cabeçalhos de cota")
struct UnifiedRateLimitHeadersTests {
    private static let readAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static func snapshot(
        _ fixture: UnifiedRateLimitHeaderFixture,
        readSequence: UInt64 = 1
    ) -> QuotaSnapshot? {
        UnifiedRateLimitHeaders.snapshot(
            from: fixture.headers,
            readSequence: readSequence,
            readAt: readAt
        )
    }

    @Test("conjunto completo produz leitura completa")
    func completeHeaderSetProducesEveryValue() throws {
        let snapshot = try #require(Self.snapshot(.complete, readSequence: 7))

        #expect(snapshot.fiveHour.utilization == Utilization(basisPoints: 7_890))
        #expect(snapshot.fiveHour.resetsAt == UnifiedRateLimitHeaderFixture.fiveHourResetsAt)
        #expect(snapshot.fiveHour.status == .allowedWarning)
        #expect(snapshot.sevenDay.utilization == Utilization(basisPoints: 1_875))
        #expect(snapshot.sevenDay.resetsAt == UnifiedRateLimitHeaderFixture.sevenDayResetsAt)
        #expect(snapshot.sevenDay.status == .allowed)
        #expect(snapshot.overallStatus == .allowedWarning)
        #expect(snapshot.nextResetAt == UnifiedRateLimitHeaderFixture.fiveHourResetsAt)
        #expect(snapshot.bindingWindow == .window(.fiveHour))
        #expect(snapshot.fallbackPercentage == Utilization(basisPoints: 4_200))
        #expect(snapshot.overage.status == "disabled")
        #expect(snapshot.overage.disabledReason == "not_enrolled")
        #expect(snapshot.readAt == Self.readAt)
        #expect(snapshot.readSequence == 7)
        #expect(snapshot.source == .primaryProbe)
    }

    @Test("a janela semanal também é mapeada quando é ela que limita")
    func sevenDayIsMappedAsBindingWindow() throws {
        var fixture = UnifiedRateLimitHeaderFixture.complete
        fixture.representativeClaim = "seven_day"

        let snapshot = try #require(Self.snapshot(fixture))

        #expect(snapshot.bindingWindow == .window(.sevenDay))
    }

    @Test("cabeçalho ausente vira indisponível, não zero")
    func missingHeaderBecomesUnavailable() throws {
        var fixture = UnifiedRateLimitHeaderFixture.complete
        fixture.sevenDayReset = nil
        fixture.fallbackPercentage = nil
        fixture.overageStatus = nil

        let snapshot = try #require(Self.snapshot(fixture))

        #expect(snapshot.sevenDay.resetsAt == nil)
        #expect(snapshot.sevenDay.utilization == Utilization(basisPoints: 1_875))
        #expect(snapshot.fallbackPercentage == nil)
        #expect(snapshot.overage.status == nil)
    }

    @Test("a janela limitante nunca é deduzida")
    func bindingWindowIsNeverInferred() throws {
        var fixture = UnifiedRateLimitHeaderFixture.complete
        fixture.representativeClaim = nil
        fixture.fiveHourUtilization = "0.10"
        fixture.sevenDayUtilization = "0.90"

        let snapshot = try #require(Self.snapshot(fixture))

        #expect(snapshot.bindingWindow == nil)
        #expect(snapshot.fiveHour.utilization == Utilization(basisPoints: 1_000))
        #expect(snapshot.sevenDay.utilization == Utilization(basisPoints: 9_000))
    }

    @Test("sem nenhuma utilização não há leitura")
    func readingWithoutAnyUtilizationIsInvalid() {
        var fixture = UnifiedRateLimitHeaderFixture.complete
        fixture.fiveHourUtilization = nil
        fixture.sevenDayUtilization = nil

        #expect(Self.snapshot(fixture) == nil)
    }

    @Test("uma utilização basta para a leitura valer")
    func oneUtilizationIsEnough() throws {
        var fixture = UnifiedRateLimitHeaderFixture.complete
        fixture.sevenDayUtilization = nil

        let snapshot = try #require(Self.snapshot(fixture))

        #expect(snapshot.fiveHour.utilization == Utilization(basisPoints: 7_890))
        #expect(snapshot.sevenDay.utilization == nil)
    }

    @Test("valor desconhecido em campo enumerado é preservado")
    func unknownEnumeratedValueIsPreserved() throws {
        var fixture = UnifiedRateLimitHeaderFixture.complete
        fixture.fiveHourStatus = "throttled_soft"
        fixture.overallStatus = "degraded"
        fixture.representativeClaim = "seven_day_opus"

        let snapshot = try #require(Self.snapshot(fixture))

        #expect(snapshot.fiveHour.status == .unknown("throttled_soft"))
        #expect(snapshot.overallStatus == .unknown("degraded"))
        #expect(snapshot.bindingWindow == .unrecognized("seven_day_opus"))
    }

    @Test(
        "utilização ilegível ou fora de faixa fica indisponível",
        arguments: ["", "   ", "abc", "0x10", "1,5", "0.5abc", "-0.1", "1e2", "NaN", "０.５"]
    )
    func unreadableUtilizationNeverBecomesZero(raw: String) throws {
        var fixture = UnifiedRateLimitHeaderFixture.complete
        fixture.fiveHourUtilization = raw

        let snapshot = try #require(Self.snapshot(fixture))

        #expect(snapshot.fiveHour.utilization == nil)
    }

    @Test(
        "instante de reset ilegível ou fora de faixa fica indisponível",
        arguments: ["", "later", "-5", "0", "1700003600.5", "17e8", "99999999999999999999"]
    )
    func unreadableResetNeverBecomesEpochZero(raw: String) throws {
        var fixture = UnifiedRateLimitHeaderFixture.complete
        fixture.fiveHourReset = raw

        let snapshot = try #require(Self.snapshot(fixture))

        #expect(snapshot.fiveHour.resetsAt == nil)
    }

    @Test("a aritmética é em pontos-base, sem ponto flutuante")
    func utilizationIsFixedPoint() throws {
        var fixture = UnifiedRateLimitHeaderFixture.complete
        fixture.fiveHourUtilization = "1.18"

        let snapshot = try #require(Self.snapshot(fixture))
        let utilization = try #require(snapshot.fiveHour.utilization)

        #expect(utilization.basisPoints == 11_800)
        #expect(utilization.truncatedPercent == 118)
        #expect(utilization.isAtOrAboveLimit)
    }

    @Test("cota esgotada chega como leitura, com utilização no limite")
    func exhaustedHeadersStillProduceAReading() throws {
        let snapshot = try #require(Self.snapshot(.exhausted))

        #expect(snapshot.fiveHour.utilization?.isAtOrAboveLimit == true)
        #expect(snapshot.fiveHour.status == .rejected)
        #expect(snapshot.overallStatus == .rejected)
    }

    @Test("o nome do cabeçalho é lido sem depender de caixa nem de espaço em volta")
    func headerNamesAreCaseInsensitiveAndValuesAreTrimmed() throws {
        let uppercased = Dictionary(
            uniqueKeysWithValues: UnifiedRateLimitHeaderFixture.complete.headers.map {
                ($0.key.uppercased(), " \($0.value) ")
            }
        )

        let snapshot = try #require(
            UnifiedRateLimitHeaders.snapshot(from: uppercased, readSequence: 1, readAt: Self.readAt)
        )

        #expect(snapshot.fiveHour.utilization == Utilization(basisPoints: 7_890))
        #expect(snapshot.fiveHour.resetsAt == UnifiedRateLimitHeaderFixture.fiveHourResetsAt)
        #expect(snapshot.bindingWindow == .window(.fiveHour))
    }

    @Test("cabeçalhos idênticos em leituras distintas produzem identidades distintas")
    func identicalHeadersKeepDistinctIdentities() throws {
        let first = try #require(Self.snapshot(.complete, readSequence: 1))
        let second = try #require(Self.snapshot(.complete, readSequence: 2))

        #expect(first.readSequence != second.readSequence)
        #expect(first != second)
        #expect(first.fiveHour.utilization == second.fiveHour.utilization)
    }
}
