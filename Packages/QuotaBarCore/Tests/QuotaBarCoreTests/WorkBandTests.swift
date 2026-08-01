import Foundation
import Testing
@testable import QuotaBarCore

private let epoch = Date(timeIntervalSince1970: 1_780_000_000)
private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func tokens(_ value: Int) -> TokenCounts {
    TokenCounts(input: 0, output: value, cacheRead: 0, cacheCreation: 0)
}

private func band(_ worked: Int, of whole: Int) -> WorkBand {
    WorkBand.of(tokens(worked), inTotal: tokens(whole))
}

@Suite("Faixa de trabalho de um modelo no período")
struct WorkBandTests {
    @Test("num período de mil tokens, as fronteiras de cem e de quinhentos separam as quatro faixas")
    func boundariesSeparateTheFourBands() {
        let worked = [0, 1, 100, 101, 500, 501, 600]

        #expect(
            worked.map { band($0, of: 1_000) } == [
                .absent, .light, .light, .steady, .steady, .intense, .intense
            ]
        )
    }

    @Test("as nove participações que cobrem as quatro faixas e as duas fronteiras resolvem numa faixa só")
    func everyParticipationResolvesToExactlyOneBand() {
        let worked = [0, 0, 400, 9_900, 10_000, 10_100, 30_000, 49_900, 50_100]

        #expect(
            worked.map { band($0, of: 100_000) } == [
                .absent, .absent, .light, .light, .light, .steady, .steady, .steady, .intense
            ]
        )
    }

    @Test("a faixa depende da proporção e não do tamanho: um terço é constante e três quartos são intensos")
    func theBandFollowsTheProportionAndNotTheSize() {
        let aThirdOfALittle = band(300, of: 900)
        let aThirdOfALot = band(3_000_000, of: 9_000_000)
        let threeQuartersOfALittle = band(300, of: 400)
        let threeQuartersOfALot = band(3_000_000, of: 4_000_000)

        #expect(aThirdOfALittle == .steady)
        #expect(aThirdOfALot == .steady)
        #expect(threeQuartersOfALittle == .intense)
        #expect(threeQuartersOfALot == .intense)
    }

    @Test("identificador de modelo que o aplicativo não conhece resolve a faixa pela mesma regra")
    func anUnknownIdentifierResolvesByTheSameRule() {
        let newcomer = ModelIdentity(recorded: "modelo-lancado-depois-desta-entrega")
        let established = ModelIdentity(recorded: "claude-opus-5")
        let period = totalsByModel(
            of: fold([
                Event(model: newcomer, worked: 600, hoursAgo: 1),
                Event(model: established, worked: 400, hoursAgo: 1)
            ])
        )

        #expect(WorkBand.of(period.of(newcomer), inTotal: period.whole) == .intense)
        #expect(WorkBand.of(period.of(established), inTotal: period.whole) == .steady)
    }

    @Test("modelo com registros e zero token não trabalhou pouco: não trabalhou, e continua listado")
    func recordsWithoutTokensAreAbsenceAndStayListed() {
        let idle = ModelIdentity(recorded: "claude-sonnet-4")
        let busyElsewhere = ModelIdentity(recorded: "claude-opus-5")
        let carryingThePeriod = ModelIdentity(recorded: "claude-haiku-4")
        let aggregate = fold(
            [
                Event(model: busyElsewhere, worked: 900, hoursAgo: 30),
                Event(model: carryingThePeriod, worked: 500, hoursAgo: 2)
            ] + (0..<28).map { Event(model: idle, worked: 0, hoursAgo: 1, ordinal: $0) }
        )
        let today = totalsByModel(of: aggregate, over: .today)

        #expect(today.whole == tokens(500))
        #expect(aggregate.models.contains(idle))
        #expect(aggregate.models.contains(busyElsewhere))
        #expect(today.of(idle) == .zero)
        #expect(WorkBand.of(today.of(idle), inTotal: today.whole) == .absent)
        #expect(WorkBand.of(today.of(busyElsewhere), inTotal: today.whole) == .absent)
    }
}

private struct Event {
    let model: ModelIdentity
    let worked: Int
    let hoursAgo: Int
    var ordinal = 0

    var record: UsageRecord {
        UsageRecord(
            key: UsageKey(value: "\(model.recordedIdentifier)-\(hoursAgo)-\(ordinal)", origin: .messageID),
            occurredAt: epoch.addingTimeInterval(TimeInterval(-hoursAgo * 3_600)),
            contributions: [ModelContribution(model: model, counts: tokens(worked))]
        )
    }
}

private struct PeriodTotals {
    let byModel: [ModelIdentity: TokenCounts]

    func of(_ model: ModelIdentity) -> TokenCounts { byModel[model] ?? .zero }

    var whole: TokenCounts { byModel.values.reduce(.zero, +) }
}

private func fold(_ events: [Event]) -> UsageAggregate {
    var fold = UsageFold(now: epoch, calendar: utc)
    fold.noteFileRead()
    for (index, event) in events.enumerated() {
        fold.absorb(event.record, at: ScanPosition(fileOrdinal: 0, lineOrdinal: index))
    }
    return fold.finish().aggregate
}

private func totalsByModel(of aggregate: UsageAggregate, over window: SeriesWindow = .everything) -> PeriodTotals {
    let buckets = aggregate.series(over: window, now: epoch, calendar: utc).buckets
    return PeriodTotals(
        byModel: buckets.reduce(into: [:]) { totals, bucket in
            for (model, counts) in bucket.byModel { totals[model, default: .zero] += counts }
        }
    )
}
