import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Taxa de consumo e projeção de esgotamento")
struct ProjectionTests {
    private static func project(
        _ series: QuotaSampleSeries,
        window: QuotaWindow = .fiveHour,
        sinceResetAt: String,
        maxIdleCadence: Duration = .seconds(900),
        now: String
    ) -> Projection {
        ProjectionPolicy.project(
            series,
            window: window,
            sinceResetAt: TestSeries.instant(sinceResetAt),
            maxIdleCadence: maxIdleCadence,
            now: TestSeries.instant(now)
        )
    }

    @Test("a taxa usa apenas as amostras posteriores ao reset da janela corrente")
    func theRateIgnoresSamplesOfThePreviousWindow() throws {
        let series = TestSeries.fiveHourSeries([
            (at: "2026-08-01T09:00:00Z", percent: "70.00"),
            (at: "2026-08-01T09:50:00Z", percent: "80.00"),
            (at: "2026-08-01T10:40:00Z", percent: "90.00"),
            (at: "2026-08-01T11:30:00Z", percent: "95.00"),
            (at: "2026-08-01T12:10:00Z", percent: "10.00"),
            (at: "2026-08-01T12:40:00Z", percent: "14.00"),
            (at: "2026-08-01T13:00:00Z", percent: "18.00"),
            (at: "2026-08-01T13:30:00Z", percent: "22.00")
        ])

        let result = Self.project(series, sinceResetAt: "2026-08-01T12:00:00Z", now: "2026-08-01T13:35:00Z")
        let basis = try #require(result.basis)

        #expect(result.ratePerHour == 9.0)
        #expect(basis.sampleCount == 4)
        #expect(basis.firstSampleAt == TestSeries.instant("2026-08-01T12:10:00Z"))
        #expect(basis.lastSampleAt == TestSeries.instant("2026-08-01T13:30:00Z"))
    }

    @Test("percentual constante e percentual decrescente dão ausência de consumo, e nunca um instante distante")
    func aNonPositiveRateNeverProjects() {
        let constant = TestSeries.fiveHourSeries([
            (at: "2026-08-01T10:00:00Z", percent: "40.00"),
            (at: "2026-08-01T10:30:00Z", percent: "40.00"),
            (at: "2026-08-01T11:00:00Z", percent: "40.00")
        ])
        let decreasing = TestSeries.fiveHourSeries([
            (at: "2026-08-01T10:00:00Z", percent: "40.00"),
            (at: "2026-08-01T10:30:00Z", percent: "39.00"),
            (at: "2026-08-01T11:00:00Z", percent: "38.00")
        ])

        for series in [constant, decreasing] {
            let result = Self.project(series, sinceResetAt: "2026-08-01T09:00:00Z", now: "2026-08-01T11:05:00Z")

            #expect(result.hasNoObservedConsumption)
            #expect(result.projectedExhaustion == nil)
            #expect(result.basis != nil)
        }

        #expect(
            Self.project(constant, sinceResetAt: "2026-08-01T09:00:00Z", now: "2026-08-01T11:05:00Z")
                .ratePerHour == 0
        )
        #expect(
            Self.project(decreasing, sinceResetAt: "2026-08-01T09:00:00Z", now: "2026-08-01T11:05:00Z")
                .ratePerHour == -2.0
        )
    }

    @Test("o esgotamento que cai antes do reset é projetado")
    func exhaustionBeforeTheResetIsProjected() throws {
        let series = TestSeries.fiveHourSeries(
            [
                (at: "2026-08-01T14:00:00Z", percent: "60.00"),
                (at: "2026-08-01T14:30:00Z", percent: "70.00"),
                (at: "2026-08-01T15:00:00Z", percent: "80.00")
            ],
            resetsAt: "2026-08-01T17:00:00Z"
        )

        let exhaustion = try #require(
            Self.project(series, sinceResetAt: "2026-08-01T12:00:00Z", now: "2026-08-01T15:00:00Z")
                .projectedExhaustion
        )

        #expect(exhaustion.at == TestSeries.instant("2026-08-01T16:00:00Z"))
        #expect(exhaustion.ratePerHour == 20.0)
        #expect(exhaustion.basis.resetInstantKnown)
    }

    @Test("o reset que chega antes do esgotamento não produz instante de esgotamento")
    func theResetArrivingFirstProducesNoExhaustionInstant() throws {
        let series = TestSeries.fiveHourSeries(
            [
                (at: "2026-08-01T14:00:00Z", percent: "20.00"),
                (at: "2026-08-01T14:30:00Z", percent: "22.00"),
                (at: "2026-08-01T15:00:00Z", percent: "24.00")
            ],
            resetsAt: "2026-08-01T17:00:00Z"
        )

        let result = Self.project(series, sinceResetAt: "2026-08-01T12:00:00Z", now: "2026-08-01T15:00:00Z")

        #expect(result.resetPrecedingExhaustion == TestSeries.instant("2026-08-01T17:00:00Z"))
        #expect(result.projectedExhaustion == nil)
        #expect(result.basis != nil)
        #expect(result.ratePerHour == 4.0)
    }

    @Test("todo resultado com taxa traz a base: contagem, primeira e última amostra e fração coberta")
    func everyResultThatHasABasisCarriesTheFourElements() throws {
        let projected = TestSeries.fiveHourSeries(
            [
                (at: "2026-08-01T14:00:00Z", percent: "60.00"),
                (at: "2026-08-01T14:30:00Z", percent: "70.00"),
                (at: "2026-08-01T15:00:00Z", percent: "80.00")
            ],
            resetsAt: "2026-08-01T17:00:00Z"
        )
        let resetsFirst = TestSeries.fiveHourSeries(
            [
                (at: "2026-08-01T14:00:00Z", percent: "20.00"),
                (at: "2026-08-01T14:30:00Z", percent: "22.00"),
                (at: "2026-08-01T15:00:00Z", percent: "24.00")
            ],
            resetsAt: "2026-08-01T17:00:00Z"
        )
        let idle = TestSeries.fiveHourSeries([
            (at: "2026-08-01T14:00:00Z", percent: "40.00"),
            (at: "2026-08-01T14:30:00Z", percent: "40.00"),
            (at: "2026-08-01T15:00:00Z", percent: "40.00")
        ])

        for series in [projected, resetsFirst, idle] {
            let basis = try #require(
                Self.project(series, sinceResetAt: "2026-08-01T13:00:00Z", now: "2026-08-01T15:00:00Z").basis
            )

            #expect(basis.sampleCount == 3)
            #expect(basis.firstSampleAt == TestSeries.instant("2026-08-01T14:00:00Z"))
            #expect(basis.lastSampleAt == TestSeries.instant("2026-08-01T15:00:00Z"))
            #expect(basis.coveredFractionOfElapsedWindow == 0.5)
        }
    }

    @Test("a fração coberta é a extensão das amostras sobre a janela já decorrida")
    func theCoveredFractionIsTheSpanOverTheElapsedWindow() throws {
        let series = TestSeries.fiveHourSeries([
            (at: "2026-08-01T12:10:00Z", percent: "10.00"),
            (at: "2026-08-01T12:40:00Z", percent: "14.00"),
            (at: "2026-08-01T13:10:00Z", percent: "18.00"),
            (at: "2026-08-01T13:30:00Z", percent: "22.00")
        ])

        let basis = try #require(
            Self.project(series, sinceResetAt: "2026-08-01T12:00:00Z", now: "2026-08-01T13:35:00Z").basis
        )

        #expect(basis.coveredFractionOfElapsedWindow == 80.0 / 95.0)
    }

    @Test("o instante da janela de cinco horas é arredondado ao múltiplo de 5 minutos mais próximo, para baixo e para cima")
    func theFiveHourInstantIsRoundedToTheNearestFiveMinutes() throws {
        let roundsDown = TestSeries.fiveHourSeries([
            (at: "2026-08-01T15:00:00Z", percent: "94.90"),
            (at: "2026-08-01T15:30:00Z", percent: "97.40"),
            (at: "2026-08-01T16:00:00Z", percent: "99.90")
        ])
        let roundsUp = TestSeries.fiveHourSeries([
            (at: "2026-08-01T15:00:00Z", percent: "62.43"),
            (at: "2026-08-01T15:30:00Z", percent: "80.00"),
            (at: "2026-08-01T16:00:00Z", percent: "98.43")
        ])

        let downwards = try #require(
            Self.project(roundsDown, sinceResetAt: "2026-08-01T14:00:00Z", now: "2026-08-01T16:00:00Z")
                .projectedExhaustion
        )
        let upwards = try #require(
            Self.project(roundsUp, sinceResetAt: "2026-08-01T14:00:00Z", now: "2026-08-01T16:00:00Z")
                .projectedExhaustion
        )

        #expect(downwards.at == TestSeries.instant("2026-08-01T16:00:00Z"))
        #expect(upwards.at == TestSeries.instant("2026-08-01T16:05:00Z"))
        #expect(Self.secondsOfMinute(downwards.at) == 0)
        #expect(Self.secondsOfMinute(upwards.at) == 0)
    }

    @Test("o instante da janela semanal é arredondado à hora mais próxima, e nunca carrega minuto nem segundo")
    func theSevenDayInstantIsRoundedToTheNearestHour() throws {
        let series = TestSeries.sevenDaySeries([
            (at: "2026-08-04T15:00:00Z", percent: "23.90"),
            (at: "2026-08-04T21:00:00Z", percent: "59.90"),
            (at: "2026-08-05T03:00:00Z", percent: "95.90")
        ])

        let exhaustion = try #require(
            Self.project(
                series,
                window: .sevenDay,
                sinceResetAt: "2026-08-04T09:00:00Z",
                maxIdleCadence: .seconds(6 * 3_600),
                now: "2026-08-05T03:00:00Z"
            ).projectedExhaustion
        )

        #expect(exhaustion.at == TestSeries.instant("2026-08-05T04:00:00Z"))
        #expect(Self.secondsOfMinute(exhaustion.at) == 0)
        #expect(Self.minutesOfHour(exhaustion.at) == 0)
    }

    @Test("janela com percentual em 100% é fato medido, e não projeção")
    func anExhaustedWindowIsNotProjected() {
        let series = TestSeries.sevenDaySeries(
            [
                (at: "2026-08-04T15:00:00Z", percent: "94.00"),
                (at: "2026-08-04T21:00:00Z", percent: "97.00"),
                (at: "2026-08-05T03:00:00Z", percent: "100.00")
            ],
            resetsAt: "2026-08-07T09:00:00Z"
        )

        let result = Self.project(
            series,
            window: .sevenDay,
            sinceResetAt: "2026-08-04T09:00:00Z",
            maxIdleCadence: .seconds(6 * 3_600),
            now: "2026-08-05T03:05:00Z"
        )

        #expect(result.isExhausted)
        #expect(result.exhaustedResetsAt == TestSeries.instant("2026-08-07T09:00:00Z"))
        #expect(result.projectedExhaustion == nil)
    }

    @Test("reset desconhecido declara a omissão e não supõe um reset")
    func anUnknownResetIsDeclaredAndNeverSupposed() throws {
        let series = TestSeries.fiveHourSeries([
            (at: "2026-08-01T14:00:00Z", percent: "60.00"),
            (at: "2026-08-01T14:30:00Z", percent: "70.00"),
            (at: "2026-08-01T15:00:00Z", percent: "80.00")
        ])

        let exhaustion = try #require(
            Self.project(series, sinceResetAt: "2026-08-01T12:00:00Z", now: "2026-08-01T15:00:00Z")
                .projectedExhaustion
        )

        #expect(exhaustion.at == TestSeries.instant("2026-08-01T16:00:00Z"))
        #expect(!exhaustion.basis.resetInstantKnown)
    }

    @Test("a série vazia é indisponível porque o histórico começa na primeira leitura, e não é ausência de consumo")
    func anEmptySeriesIsUnavailableAndNotAbsenceOfConsumption() {
        let result = Self.project(
            QuotaSampleSeries(),
            sinceResetAt: "2026-08-01T12:00:00Z",
            now: "2026-08-01T15:00:00Z"
        )

        #expect(result.unavailability == .seriesBeginsAtFirstReading)
        #expect(!result.hasNoObservedConsumption)
        #expect(result.basis == nil)
        #expect(result.ratePerHour == nil)
    }

    @Test("a fronteira entre indisponível e insuficiente é o zero, e amostras de outra janela não entram na contagem")
    func theBoundaryBetweenUnavailableAndInsufficientIsZero() {
        let windowStart = TestSeries.instant("2026-08-01T12:00:00Z")
        let tenWithoutTheWindow = (1...10).map { index in
            QuotaSample(
                readAt: windowStart.addingTimeInterval(Double(index) * 300),
                readSequence: UInt64(index),
                fiveHour: TestSeries.percent("40.00"),
                sevenDay: nil,
                fiveHourResetsAt: nil,
                sevenDayResetsAt: nil,
                source: .primaryProbe
            )
        }
        let twoWithTheWindow = [
            TestSeries.sample(at: "2026-08-01T13:10:00Z", sequence: 11, sevenDay: "20.00"),
            TestSeries.sample(at: "2026-08-01T13:40:00Z", sequence: 12, sevenDay: "24.00")
        ]

        let withoutAny = Self.project(
            QuotaSampleSeries(tenWithoutTheWindow),
            window: .sevenDay,
            sinceResetAt: "2026-08-01T12:00:00Z",
            now: "2026-08-01T14:00:00Z"
        )
        let withTwo = Self.project(
            QuotaSampleSeries(tenWithoutTheWindow + twoWithTheWindow),
            window: .sevenDay,
            sinceResetAt: "2026-08-01T12:00:00Z",
            now: "2026-08-01T14:00:00Z"
        )

        #expect(withoutAny.unavailability == .noUtilizationForWindow)
        #expect(withTwo.insufficiency == .quantity(observed: 2, required: 3))
    }

    @Test("a janela sem percentual nenhum é indisponível, e não é ausência de consumo")
    func aWindowWithoutAnyUtilizationIsUnavailable() {
        let series = TestSeries.fiveHourSeries([
            (at: "2026-08-01T14:00:00Z", percent: "60.00"),
            (at: "2026-08-01T14:30:00Z", percent: "70.00")
        ])

        let result = Self.project(
            series,
            window: .sevenDay,
            sinceResetAt: "2026-08-01T12:00:00Z",
            now: "2026-08-01T15:00:00Z"
        )

        #expect(result.unavailability == .noUtilizationForWindow)
        #expect(!result.hasNoObservedConsumption)
    }

    @Test("a política pede 3 amostras e 5% da janela, tolera o dobro da cadência e arredonda a 5 minutos e a 1 hora")
    func thePolicyConstantsAreTheOnesInTheSpec() {
        #expect(ProjectionPolicy.minimumSamples == 3)
        #expect(ProjectionPolicy.minimumSpanFractionOfWindow == 0.05)
        #expect(ProjectionPolicy.gapToleranceFactor == 2)
        #expect(ProjectionPolicy.granularity(for: .fiveHour) == .seconds(300))
        #expect(ProjectionPolicy.granularity(for: .sevenDay) == .seconds(3_600))
        #expect(ProjectionPolicy.minimumSpan(for: .fiveHour) == .seconds(900))
        #expect(ProjectionPolicy.minimumSpan(for: .sevenDay) == .seconds(30_240))
    }

    private static func secondsOfMinute(_ date: Date) -> Int {
        calendar.component(.second, from: date)
    }

    private static func minutesOfHour(_ date: Date) -> Int {
        calendar.component(.minute, from: date)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
