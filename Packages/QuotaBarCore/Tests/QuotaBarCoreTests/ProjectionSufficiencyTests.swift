import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Suficiência da amostra para taxa e projeção")
struct ProjectionSufficiencyTests {
    private static let windowStart = TestSeries.instant("2026-08-01T09:00:00Z")

    private static func project(
        _ series: QuotaSampleSeries,
        window: QuotaWindow = .fiveHour,
        sinceResetAt: Date = windowStart,
        maxIdleCadence: Duration = .seconds(900),
        now: String
    ) -> Projection {
        ProjectionPolicy.project(
            series,
            window: window,
            sinceResetAt: sinceResetAt,
            maxIdleCadence: maxIdleCadence,
            now: TestSeries.instant(now)
        )
    }

    @Test("duas amostras não sustentam taxa, e o motivo devolvido é quantidade")
    func twoSamplesAreNotEnough() {
        let series = TestSeries.fiveHourSeries([
            (at: "2026-08-01T10:00:00Z", percent: "10.00"),
            (at: "2026-08-01T10:40:00Z", percent: "20.00")
        ])

        let result = Self.project(series, now: "2026-08-01T10:45:00Z")

        #expect(result.insufficiency == .quantity(observed: 2, required: 3))
        #expect(result.ratePerHour == nil)
        #expect(result.basis == nil)
    }

    @Test("a janela de cinco horas exige 15 minutos de extensão, e um segundo a menos não basta")
    func theFiveHourWindowRequiresFifteenMinutesOfSpan() {
        let short = TestSeries.fiveHourSeries([
            (at: "2026-08-01T10:00:00Z", percent: "10.00"),
            (at: "2026-08-01T10:07:00Z", percent: "12.00"),
            (at: "2026-08-01T10:14:59Z", percent: "14.00")
        ])
        let long = TestSeries.fiveHourSeries([
            (at: "2026-08-01T10:00:00Z", percent: "10.00"),
            (at: "2026-08-01T10:07:00Z", percent: "12.00"),
            (at: "2026-08-01T10:15:00Z", percent: "14.00")
        ])

        #expect(
            Self.project(short, now: "2026-08-01T10:20:00Z").insufficiency
                == .span(observed: .seconds(899), required: .seconds(900))
        )
        #expect(!Self.project(long, now: "2026-08-01T10:20:00Z").isInsufficient)
    }

    @Test("a janela semanal exige 8 horas e 24 minutos de extensão, e um minuto a menos não basta")
    func theSevenDayWindowRequiresEightHoursAndTwentyFourMinutesOfSpan() {
        let short = TestSeries.sevenDaySeries([
            (at: "2026-08-01T00:00:00Z", percent: "10.00"),
            (at: "2026-08-01T04:00:00Z", percent: "12.00"),
            (at: "2026-08-01T08:23:00Z", percent: "14.00")
        ])
        let long = TestSeries.sevenDaySeries([
            (at: "2026-08-01T00:00:00Z", percent: "10.00"),
            (at: "2026-08-01T04:00:00Z", percent: "12.00"),
            (at: "2026-08-01T08:24:00Z", percent: "14.00")
        ])
        let start = TestSeries.instant("2026-07-31T23:00:00Z")

        #expect(
            Self.project(
                short,
                window: .sevenDay,
                sinceResetAt: start,
                maxIdleCadence: .seconds(4 * 3_600),
                now: "2026-08-01T09:00:00Z"
            ).insufficiency == .span(observed: .seconds(30_180), required: .seconds(30_240))
        )
        #expect(
            !Self.project(
                long,
                window: .sevenDay,
                sinceResetAt: start,
                maxIdleCadence: .seconds(4 * 3_600),
                now: "2026-08-01T09:00:00Z"
            ).isInsufficient
        )
    }

    @Test("um buraco interno de quatro horas recusa por continuidade mesmo com quantidade e extensão satisfeitas")
    func aFourHourHoleRefusesByContinuity() {
        let series = TestSeries.fiveHourSeries([
            (at: "2026-08-01T10:00:00Z", percent: "10.00"),
            (at: "2026-08-01T10:30:00Z", percent: "12.00"),
            (at: "2026-08-01T14:30:00Z", percent: "30.00"),
            (at: "2026-08-01T15:00:00Z", percent: "32.00")
        ])

        let result = Self.project(series, maxIdleCadence: .seconds(900), now: "2026-08-01T15:05:00Z")

        #expect(
            result.insufficiency == .continuity(largestGap: .seconds(4 * 3_600), tolerated: .seconds(1_800))
        )
        #expect(result.ratePerHour == nil)
    }

    @Test("a tolerância do buraco é duas vezes a cadência de ociosidade vigente, e não um número fixo")
    func theHoleToleranceFollowsTheIdleCadence() {
        let series = TestSeries.fiveHourSeries([
            (at: "2026-08-01T10:00:00Z", percent: "10.00"),
            (at: "2026-08-01T10:25:00Z", percent: "12.00"),
            (at: "2026-08-01T10:40:00Z", percent: "14.00"),
            (at: "2026-08-01T11:00:00Z", percent: "16.00")
        ])

        let underFifteenMinuteCadence = Self.project(
            series,
            maxIdleCadence: .seconds(900),
            now: "2026-08-01T11:05:00Z"
        )
        let underTenMinuteCadence = Self.project(
            series,
            maxIdleCadence: .seconds(600),
            now: "2026-08-01T11:05:00Z"
        )

        #expect(!underFifteenMinuteCadence.isInsufficient)
        #expect(
            underTenMinuteCadence.insufficiency
                == .continuity(largestGap: .seconds(1_500), tolerated: .seconds(1_200))
        )
    }

    @Test("o buraco de exatamente duas vezes a cadência ainda passa, e um segundo além dele não passa")
    func theHoleToleranceIsInclusiveAtTheBoundary() {
        let atTolerance = TestSeries.fiveHourSeries([
            (at: "2026-08-01T10:00:00Z", percent: "10.00"),
            (at: "2026-08-01T10:30:00Z", percent: "12.00"),
            (at: "2026-08-01T10:45:00Z", percent: "25.00")
        ])
        let oneSecondBeyond = TestSeries.fiveHourSeries([
            (at: "2026-08-01T10:00:00Z", percent: "10.00"),
            (at: "2026-08-01T10:30:01Z", percent: "12.00"),
            (at: "2026-08-01T10:45:00Z", percent: "25.00")
        ])

        #expect(Self.project(atTolerance, now: "2026-08-01T10:50:00Z").ratePerHour == 20.0)
        #expect(
            Self.project(oneSecondBeyond, now: "2026-08-01T10:50:00Z").insufficiency
                == .continuity(largestGap: .seconds(1_801), tolerated: .seconds(1_800))
        )
    }

    @Test("a amostra com instante no futuro é descartada antes de a suficiência ser avaliada")
    func futureSamplesAreFilteredBeforeSufficiency() {
        let series = TestSeries.fiveHourSeries([
            (at: "2026-08-01T10:00:00Z", percent: "10.00"),
            (at: "2026-08-01T10:30:00Z", percent: "12.00"),
            (at: "2026-08-01T11:00:00Z", percent: "14.00"),
            (at: "2026-08-01T11:30:00Z", percent: "16.00")
        ])

        let withFutureSamples = Self.project(series, now: "2026-08-01T10:45:00Z")
        let withAllSamplesInThePast = Self.project(series, now: "2026-08-01T11:35:00Z")

        #expect(withFutureSamples.insufficiency == .quantity(observed: 2, required: 3))
        #expect(!withAllSamplesInThePast.isInsufficient)
        #expect(withAllSamplesInThePast.basis?.sampleCount == 4)
    }

    @Test("esgotada vence quantidade, extensão e continuidade, porque é fato medido")
    func exhaustedWinsOverEverySufficiencyCondition() {
        let series = Self.seriesViolatingEverySufficiencyCondition(from: "105.00", to: "100.00")

        let result = Self.project(series, maxIdleCadence: .seconds(60), now: "2026-08-01T10:05:00Z")

        #expect(result.isExhausted)
        #expect(result.exhaustedResetsAt == TestSeries.instant("2026-08-01T14:00:00Z"))
    }

    @Test("sem esgotada, o motivo é quantidade, e nunca uma lista de motivos")
    func quantityBitesBeforeSpanAndContinuity() {
        let series = Self.seriesViolatingEverySufficiencyCondition(from: "45.00", to: "40.00")

        let result = Self.project(series, maxIdleCadence: .seconds(60), now: "2026-08-01T10:05:00Z")

        #expect(result.insufficiency == .quantity(observed: 2, required: 3))
    }

    private static func seriesViolatingEverySufficiencyCondition(
        from: String,
        to: String
    ) -> QuotaSampleSeries {
        TestSeries.fiveHourSeries(
            [
                (at: "2026-08-01T10:00:00Z", percent: from),
                (at: "2026-08-01T10:03:00Z", percent: to)
            ],
            resetsAt: "2026-08-01T14:00:00Z"
        )
    }

    @Test("amostras no mesmo instante não produzem extensão, e a recusa é por extensão")
    func samplesSharingTheSameInstantHaveNoSpan() {
        let series = TestSeries.fiveHourSeries([
            (at: "2026-08-01T10:00:00Z", percent: "10.00"),
            (at: "2026-08-01T10:00:00Z", percent: "12.00"),
            (at: "2026-08-01T10:00:00Z", percent: "14.00")
        ])

        #expect(
            Self.project(series, now: "2026-08-01T10:05:00Z").insufficiency
                == .span(observed: .zero, required: .seconds(900))
        )
    }
}
