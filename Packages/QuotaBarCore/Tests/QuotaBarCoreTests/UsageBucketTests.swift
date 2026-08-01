import Foundation
import Testing
@testable import QuotaBarCore

private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private let newYork = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

private func instant(_ text: String) -> Date {
    try! Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(text)
}

private func aggregate(
    events: [(Date, Int)],
    calendar: Calendar,
    now: Date,
    intact: Bool = true
) -> UsageAggregate {
    var fold = UsageFold(now: now, calendar: calendar)
    fold.noteFileRead()
    if !intact { fold.noteFileUnread() }

    for (offset, event) in events.enumerated() {
        let record = UsageRecord(
            key: UsageKey(value: "msg_\(offset)", origin: .messageID),
            occurredAt: event.0,
            contributions: [
                ModelContribution(
                    model: .model("claude-opus-5"),
                    counts: TokenCounts(input: 0, output: event.1, cacheRead: 0, cacheCreation: 0)
                )
            ]
        )
        fold.absorb(record, at: ScanPosition(fileOrdinal: 0, lineOrdinal: offset))
    }

    return fold.finish().aggregate
}

@Suite("Baldes, cobertura e decimação")
struct UsageBucketTests {
    @Test("o período define a duração do balde, e 200 dias levam `tudo` à semana")
    func periodDecidesBucketSize() {
        let now = instant("2026-08-01T12:00:00Z")
        let spread = (0..<200).map { (now.addingTimeInterval(Double(-$0) * 86_400), 10) }
        let wide = aggregate(events: spread, calendar: utc, now: now)

        #expect(DisplayGranularity.bucketSize(for: .today, coverage: wide.coverage) == .hour)
        #expect(DisplayGranularity.bucketSize(for: .week, coverage: wide.coverage) == .hour)
        #expect(DisplayGranularity.bucketSize(for: .month, coverage: wide.coverage) == .day)
        #expect(DisplayGranularity.bucketSize(for: .everything, coverage: wide.coverage) == .week)

        let narrow = aggregate(
            events: (0..<10).map { (now.addingTimeInterval(Double(-$0) * 86_400), 10) },
            calendar: utc,
            now: now
        )
        #expect(DisplayGranularity.bucketSize(for: .everything, coverage: narrow.coverage) == .day)
    }

    @Test("balde vazio vale zero sob cobertura íntegra e é ausência sob cobertura rota")
    func emptyBucketMeaningDependsOnCoverage() {
        let now = instant("2026-08-01T20:00:00Z")
        let events = [
            (instant("2026-08-01T14:10:00Z"), 100),
            (instant("2026-08-01T14:40:00Z"), 200)
        ]

        let intact = aggregate(events: events, calendar: utc, now: now)
        let intactSeries = intact.series(over: .today, now: now, calendar: utc)
        #expect(intactSeries.buckets.count == 1)
        #expect(intactSeries.buckets.first?.value == .measured(
            TokenCounts(input: 0, output: 300, cacheRead: 0, cacheCreation: 0)
        ))

        let spread = events + [(instant("2026-08-01T16:20:00Z"), 50)]
        let intactSpread = aggregate(events: spread, calendar: utc, now: now)
            .series(over: .today, now: now, calendar: utc)
        #expect(intactSpread.buckets.count == 3)
        #expect(intactSpread.buckets[1].value == .measured(.zero))

        let broken = aggregate(events: spread, calendar: utc, now: now, intact: false)
            .series(over: .today, now: now, calendar: utc)
        #expect(broken.buckets[1].value == .noCoverage)
    }

    @Test("fora do intervalo entre o primeiro e o último evento o balde não existe")
    func bucketsOutsideCoverageDoNotExist() {
        let now = instant("2026-08-01T23:00:00Z")
        let events = [
            (instant("2026-08-01T14:10:00Z"), 100),
            (instant("2026-08-01T15:10:00Z"), 200)
        ]

        let series = aggregate(events: events, calendar: utc, now: now)
            .series(over: .today, now: now, calendar: utc)

        #expect(series.buckets.count == 2)
        #expect(series.buckets.first?.key.start == instant("2026-08-01T14:00:00Z"))
        #expect(series.buckets.last?.key.start == instant("2026-08-01T15:00:00Z"))
    }

    @Test("a hora duplicada agrega as duas ocorrências e a soma fecha com o total")
    func repeatedHourAggregatesBothOccurrences() {
        let now = instant("2026-11-02T12:00:00Z")
        let events = [
            (instant("2026-11-01T05:30:00Z"), 100),
            (instant("2026-11-01T06:30:00Z"), 200)
        ]

        let built = aggregate(events: events, calendar: newYork, now: now)
        let series = built.series(over: .week, now: now, calendar: newYork)
        let measured = series.buckets.compactMap { bucket -> Int? in
            guard case .measured(let counts) = bucket.value else { return nil }
            return counts.total.value
        }

        #expect(series.buckets.count == 1)
        #expect(measured.reduce(0, +) == 300)
    }

    @Test("a hora inexistente não produz balde, e nenhum evento se perde")
    func skippedHourProducesNoBucket() {
        let now = instant("2026-03-09T12:00:00Z")
        let events = [
            (instant("2026-03-08T06:30:00Z"), 100),
            (instant("2026-03-08T08:30:00Z"), 200)
        ]

        let built = aggregate(events: events, calendar: newYork, now: now)
        let series = built.series(over: .week, now: now, calendar: newYork)

        let localHours = series.buckets.map { newYork.component(.hour, from: $0.key.start) }
        #expect(!localHours.contains(2))

        let measured = series.buckets.reduce(0) { running, bucket in
            guard case .measured(let counts) = bucket.value else { return running }
            return running + counts.total.value
        }
        #expect(measured == 300)
    }

    @Test("cada balde carrega o total por modelo, com os quatro contadores separados")
    func bucketsCarryPerModelTotals() {
        let now = instant("2026-08-01T20:00:00Z")
        var fold = UsageFold(now: now, calendar: utc)
        fold.noteFileRead()

        let moment = instant("2026-08-01T14:10:00Z")
        fold.absorb(
            UsageRecord(
                key: UsageKey(value: "msg_1", origin: .messageID),
                occurredAt: moment,
                contributions: [
                    ModelContribution(
                        model: .model("claude-opus-5"),
                        counts: TokenCounts(input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
                    ),
                    ModelContribution(
                        model: .model("claude-fable-5"),
                        counts: TokenCounts(input: 10, output: 20, cacheRead: 30, cacheCreation: 40)
                    )
                ]
            ),
            at: ScanPosition(fileOrdinal: 0, lineOrdinal: 0)
        )

        let series = fold.finish().aggregate.series(over: .today, now: now, calendar: utc)
        let bucket = series.buckets.first

        #expect(bucket?.byModel[.model("claude-opus-5")]?.total.value == 10)
        #expect(bucket?.byModel[.model("claude-fable-5")]?.total.value == 100)
        #expect(bucket?.byModel[.model("claude-opus-5")]?.cacheRead == 3)
        #expect(bucket?.value == .measured(TokenCounts(input: 11, output: 22, cacheRead: 33, cacheCreation: 44)))
    }

    @Test("mudar de período reagrega os mesmos eventos, sem releitura")
    func changingPeriodReusesTheSameEvents() {
        let now = instant("2026-08-01T20:00:00Z")
        let built = aggregate(
            events: (0..<40).map { (now.addingTimeInterval(Double(-$0) * 3_600), 10) },
            calendar: utc,
            now: now
        )

        for window in SeriesWindow.allCases {
            let series = built.series(over: window, now: now, calendar: utc)
            #expect(!series.buckets.isEmpty, "\(window) ficou sem balde")
        }
    }
}
