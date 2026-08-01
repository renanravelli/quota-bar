import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Série de leituras de cota")
struct QuotaSampleSeriesTests {
    private static let fiveHourReset = TestSeries.instant("2026-08-01T17:00:00Z")
    private static let sevenDayReset = TestSeries.instant("2026-08-04T09:00:00Z")

    private static func reading(
        at iso: String,
        sequence: UInt64,
        fiveHourPercent: String? = "40.00",
        sevenDayPercent: String? = "21.00"
    ) -> QuotaSnapshot {
        TestSnapshot.make(
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            bindingWindow: .window(.fiveHour),
            fiveHourResetsAt: fiveHourReset,
            sevenDayResetsAt: sevenDayReset,
            readSequence: sequence,
            readAt: TestSeries.instant(iso)
        )
    }

    @Test("uma leitura bem-sucedida vira exatamente uma amostra com os quatro valores publicados")
    func aSuccessfulReadingBecomesOneSample() throws {
        var series = QuotaSampleSeries()
        let snapshot = Self.reading(at: "2026-08-01T14:00:00Z", sequence: 7)

        #expect(series.coverage.isEmpty)
        let recorded = series.record(TestSeries.succeededState(snapshot))
        #expect(recorded)

        #expect(series.samples.count == 1)
        let sample = try #require(series.samples.first)
        #expect(sample.readAt == TestSeries.instant("2026-08-01T14:00:00Z"))
        #expect(sample.readSequence == 7)
        #expect(sample.fiveHour == TestSeries.percent("40.00"))
        #expect(sample.sevenDay == TestSeries.percent("21.00"))
        #expect(sample.fiveHourResetsAt == Self.fiveHourReset)
        #expect(sample.sevenDayResetsAt == Self.sevenDayReset)
    }

    @Test("reemitir o mesmo estado, com a mesma identidade de leitura, não cria amostra")
    func reissuingTheSameReadingCreatesNoSample() {
        var series = QuotaSampleSeries()
        let snapshot = Self.reading(at: "2026-08-01T14:00:00Z", sequence: 12)
        let state = TestSeries.succeededState(snapshot)

        let firstRecording = series.record(state)
        #expect(firstRecording)

        for _ in 1...3 {
            let reissued = series.record(state)
            #expect(!reissued)
        }

        #expect(series.samples.count == 1)
    }

    @Test("falha de leitura não gera amostra, e a janela sem percentual fica ausente e nunca zero")
    func aFailedAttemptCreatesNoSampleAndAbsenceIsNotZero() throws {
        var series = QuotaSampleSeries()
        series.record(TestSeries.succeededState(Self.reading(at: "2026-08-01T14:00:00Z", sequence: 1)))
        series.record(TestSeries.succeededState(Self.reading(at: "2026-08-01T14:03:00Z", sequence: 2)))

        let kept = series.samples
        let recordedFailure = series.record(
            TestSeries.failedState(.communicationFailure, keeping: kept.last.map(Self.snapshot))
        )
        #expect(!recordedFailure)
        #expect(series.samples == kept)

        let partial = Self.reading(at: "2026-08-01T14:06:00Z", sequence: 3, sevenDayPercent: nil)
        let recordedPartial = series.record(TestSeries.succeededState(partial))
        #expect(recordedPartial)

        #expect(series.samples.count == 3)
        let latest = try #require(series.samples.last)
        #expect(latest.sevenDay == nil)
        #expect(latest.utilization(of: .sevenDay) == nil)
        #expect(latest.fiveHour == TestSeries.percent("40.00"))
        #expect(series.samples(of: .sevenDay, sinceResetAt: TestSeries.instant("2026-08-01T00:00:00Z")).count == 2)
        #expect(!series.samples.contains { $0.sevenDay == TestSeries.percent("0.00") })
    }

    @Test("a série vazia é estado legítimo, e sua cobertura não tem instante nenhum")
    func anEmptySeriesIsALegitimateState() {
        let series = QuotaSampleSeries()

        #expect(series.coverage.isEmpty)
        #expect(series.coverage.earliest == nil)
        #expect(series.coverage.latest == nil)
        #expect(series.coverage.sampleCount == 0)
        #expect(series.restoration == .intact)
    }

    @Test("o período anterior à primeira amostra fica fora do domínio da série, e não é buraco")
    func thePeriodBeforeTheFirstSampleIsOutOfDomain() {
        let windowStart = TestSeries.instant("2026-07-28T09:00:00Z")
        let now = TestSeries.instant("2026-08-01T12:00:00Z")
        let firstSampleAt = TestSeries.instant("2026-08-01T09:14:00Z")
        let series = TestSeries.sevenDaySeries([
            (at: "2026-08-01T09:14:00Z", percent: "12.00"),
            (at: "2026-08-01T09:44:00Z", percent: "13.00"),
            (at: "2026-08-01T11:00:00Z", percent: "15.00")
        ])

        let current = series.samples(of: .sevenDay, sinceResetAt: windowStart)
        #expect(current.first?.readAt == firstSampleAt)
        #expect(SeriesCoverage(of: current).earliest == firstSampleAt)

        let gaps = series.gaps(of: .sevenDay, over: DateInterval(start: windowStart, end: now))
        #expect(!gaps.contains { $0.start < firstSampleAt })
        #expect(gaps.map(\.start) == [firstSampleAt, TestSeries.instant("2026-08-01T09:44:00Z")])
    }

    @Test("a série preserva os instantes originais e não sintetiza amostra para o intervalo sem execução")
    func theRestoredSeriesKeepsItsHoleAsAHole() {
        var series = TestSeries.fiveHourSeries([
            (at: "2026-08-01T09:30:00Z", percent: "10.00"),
            (at: "2026-08-01T10:00:00Z", percent: "12.00")
        ])

        series.record(TestSeries.succeededState(Self.reading(at: "2026-08-01T14:00:00Z", sequence: 9)))

        #expect(series.samples.map(\.readAt) == [
            TestSeries.instant("2026-08-01T09:30:00Z"),
            TestSeries.instant("2026-08-01T10:00:00Z"),
            TestSeries.instant("2026-08-01T14:00:00Z")
        ])
    }

    @Test("amostras chegando fora de ordem ficam ordenadas por instante")
    func samplesAreKeptOrderedByInstant() {
        var series = QuotaSampleSeries()
        series.append(TestSeries.sample(at: "2026-08-01T14:00:00Z", sequence: 2, fiveHour: "20.00"))
        series.append(TestSeries.sample(at: "2026-08-01T13:00:00Z", sequence: 1, fiveHour: "10.00"))

        #expect(series.samples.map(\.readSequence) == [1, 2])
    }

    private static func snapshot(of sample: QuotaSample) -> QuotaSnapshot {
        TestSnapshot.make(
            fiveHourPercent: "40.00",
            sevenDayPercent: "21.00",
            bindingWindow: .window(.fiveHour),
            readSequence: sample.readSequence,
            readAt: sample.readAt
        )
    }
}
