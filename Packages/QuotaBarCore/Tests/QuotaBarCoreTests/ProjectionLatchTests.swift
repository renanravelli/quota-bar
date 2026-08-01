import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Recálculo da projeção por evento, e não por tempo")
struct ProjectionLatchTests {
    private static let currentWindowStart = TestSeries.instant("2026-08-01T12:00:00Z")

    private static func series() -> QuotaSampleSeries {
        TestSeries.fiveHourSeries(
            [
                (at: "2026-08-01T14:00:00Z", percent: "60.00"),
                (at: "2026-08-01T14:30:00Z", percent: "70.00"),
                (at: "2026-08-01T15:00:00Z", percent: "80.00")
            ],
            resetsAt: "2026-08-01T17:00:00Z"
        )
    }

    private static func update(
        _ latch: inout ProjectionLatch,
        with series: QuotaSampleSeries,
        sinceResetAt: Date = currentWindowStart,
        at iso: String
    ) {
        latch.update(
            with: series,
            window: .fiveHour,
            sinceResetAt: sinceResetAt,
            maxIdleCadence: .seconds(900),
            now: TestSeries.instant(iso)
        )
    }

    @Test("sem amostra nova o instante projetado não se move, e só a idade da base acompanha o relógio")
    func timeAloneMovesTheAgeAndNotTheInstant() throws {
        var latch = ProjectionLatch()
        let series = Self.series()

        Self.update(&latch, with: series, at: "2026-08-01T15:00:00Z")
        let computedAt = latch.computedAt

        for (instant, age) in [
            ("2026-08-01T15:00:00Z", Duration.zero),
            ("2026-08-01T15:30:00Z", Duration.seconds(1_800)),
            ("2026-08-01T15:55:00Z", Duration.seconds(3_300))
        ] {
            Self.update(&latch, with: series, at: instant)

            let exhaustion = try #require(latch.projection.projectedExhaustion)
            #expect(exhaustion.at == TestSeries.instant("2026-08-01T16:00:00Z"))
            #expect(exhaustion.basis.ageOfLastSample(at: TestSeries.instant(instant)) == age)
        }

        #expect(latch.computedAt == computedAt)
    }

    @Test("uma amostra nova recalcula o resultado")
    func aNewSampleRecalculates() {
        var latch = ProjectionLatch()
        var series = Self.series()

        Self.update(&latch, with: series, at: "2026-08-01T15:00:00Z")
        let firstComputation = latch.computedAt

        series.append(
            TestSeries.sample(
                at: "2026-08-01T15:30:00Z",
                sequence: 4,
                fiveHour: "95.00",
                fiveHourResetsAt: "2026-08-01T17:00:00Z"
            )
        )
        Self.update(&latch, with: series, at: "2026-08-01T15:30:00Z")

        #expect(latch.computedAt != firstComputation)
        #expect(latch.projection.projectedExhaustion?.at == TestSeries.instant("2026-08-01T15:45:00Z"))
    }

    @Test("a mudança do instante de reset recalcula o resultado sem que uma amostra nova chegue")
    func aChangedResetInstantRecalculates() {
        var latch = ProjectionLatch()
        let series = Self.series()

        Self.update(&latch, with: series, at: "2026-08-01T15:00:00Z")
        let beforeResetChange = latch.projection

        let withEarlierReset = QuotaSampleSeries(
            Array(series.samples.dropLast()) + [
                TestSeries.sample(
                    at: "2026-08-01T15:00:00Z",
                    sequence: 3,
                    fiveHour: "80.00",
                    fiveHourResetsAt: "2026-08-01T15:30:00Z"
                )
            ]
        )
        Self.update(&latch, with: withEarlierReset, at: "2026-08-01T15:00:00Z")

        #expect(withEarlierReset.samples.count == series.samples.count)
        #expect(beforeResetChange.projectedExhaustion?.at == TestSeries.instant("2026-08-01T16:00:00Z"))
        #expect(latch.projection.resetPrecedingExhaustion == TestSeries.instant("2026-08-01T15:30:00Z"))
    }

    @Test("ultrapassado o reset, a leitura da janela nova volta o resultado a amostra insuficiente")
    func crossingTheResetReturnsToInsufficientSample() {
        var latch = ProjectionLatch()
        var series = TestSeries.fiveHourSeries(
            [
                (at: "2026-08-01T14:00:00Z", percent: "40.00"),
                (at: "2026-08-01T14:30:00Z", percent: "52.00"),
                (at: "2026-08-01T15:00:00Z", percent: "64.00"),
                (at: "2026-08-01T15:30:00Z", percent: "76.00")
            ],
            resetsAt: "2026-08-01T17:00:00Z"
        )

        Self.update(&latch, with: series, at: "2026-08-01T15:35:00Z")
        #expect(latch.projection.projectedExhaustion?.at == TestSeries.instant("2026-08-01T16:30:00Z"))

        series.append(
            TestSeries.sample(
                at: "2026-08-01T17:05:00Z",
                sequence: 5,
                fiveHour: "2.00",
                fiveHourResetsAt: "2026-08-01T22:00:00Z"
            )
        )
        Self.update(
            &latch,
            with: series,
            sinceResetAt: TestSeries.instant("2026-08-01T17:00:00Z"),
            at: "2026-08-01T17:05:00Z"
        )

        #expect(latch.projection.insufficiency == .quantity(observed: 1, required: 3))
        #expect(latch.projection.basis == nil)
    }

    @Test("antes de qualquer leitura o resultado é indisponível, e não ausência de consumo")
    func theInitialStateIsUnavailable() {
        let latch = ProjectionLatch()

        #expect(latch.projection.unavailability == .seriesBeginsAtFirstReading)
        #expect(latch.computedAt == nil)
    }
}
