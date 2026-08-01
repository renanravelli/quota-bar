import Foundation
import Testing
@testable import QuotaBarCore

private let epoch = Date(timeIntervalSince1970: 1_780_000_000)
private let horizon = epoch.addingTimeInterval(86_400)
private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private struct Line {
    let key: String
    let accumulated: Int
    let model: String
    let seconds: TimeInterval
    let bytes: Int64

    init(key: String, accumulated: Int, model: String = "claude-opus-5", seconds: TimeInterval = 0, bytes: Int64 = 128) {
        self.key = key
        self.accumulated = accumulated
        self.model = model
        self.seconds = seconds
        self.bytes = bytes
    }

    var usageKey: UsageKey { UsageKey(value: key, origin: .messageID) }

    var record: UsageRecord {
        UsageRecord(
            key: usageKey,
            occurredAt: epoch.addingTimeInterval(seconds),
            contributions: [
                ModelContribution(
                    model: ModelIdentity(recorded: model),
                    counts: TokenCounts(input: 0, output: accumulated, cacheRead: 0, cacheCreation: 0)
                )
            ]
        )
    }
}

private func rows(of lines: [Line]) -> [ScannedRow] {
    var offset: Int64 = 0
    return lines.map { line in
        defer { offset += line.bytes }
        return ScannedRow(key: line.usageKey, offset: offset, length: line.bytes)
    }
}

private let onlyFile = FileIdentity(digest: 1)

private func foldAll(_ lines: [Line], carrying ledger: UsageLedger = .empty) -> UsageFoldResult {
    var fold = UsageFold(now: horizon, calendar: utc, carrying: ledger)
    fold.noteFileRead()
    for (index, line) in lines.enumerated() {
        fold.absorb(line.record, at: ScanPosition(fileOrdinal: 0, lineOrdinal: index), from: onlyFile)
    }
    return fold.finish()
}

private func total(_ result: UsageFoldResult) -> Int {
    result.aggregate.totalsByModel.values.reduce(.zero, +).total.value
}

@Suite("A dobra, com deduplicação")
struct UsageFoldTests {
    private static let threeOccurrences = [
        Line(key: "msg_a", accumulated: 100),
        Line(key: "msg_a", accumulated: 180),
        Line(key: "msg_a", accumulated: 210)
    ]

    private static let twentyFourOccurrences = (1...24).map {
        Line(key: "msg_b", accumulated: $0 == 24 ? 4_096 : $0 * 100)
    }

    @Test("vence a última ocorrência, em 3 e em 24 — nunca a soma nem a primeira")
    func lastOccurrenceReplaces() {
        #expect(total(foldAll(Self.threeOccurrences)) == 210)
        #expect(total(foldAll(Self.twentyFourOccurrences)) == 4_096)
    }

    @Test("a regra não depende do número de repetições")
    func ruleIsAboutReplacementNotRepetition() {
        for repetitions in 1...24 {
            let lines = (1...repetitions).map { Line(key: "msg_n", accumulated: $0 * 7) }
            #expect(total(foldAll(lines)) == repetitions * 7)
        }
    }

    @Test("a deduplicação atravessa arquivos e conta a duplicata descartada")
    func deduplicationCrossesFiles() {
        var fold = UsageFold(now: horizon, calendar: utc)
        fold.noteFileRead()
        fold.noteFileRead()
        let line = Line(key: "msg_shared", accumulated: 500)
        fold.absorb(
            line.record,
            at: ScanPosition(fileOrdinal: 0, lineOrdinal: 0),
            from: FileIdentity(digest: 1)
        )
        fold.absorb(
            Line(key: "msg_shared", accumulated: 900).record,
            at: ScanPosition(fileOrdinal: 1, lineOrdinal: 0),
            from: FileIdentity(digest: 2)
        )

        let result = fold.finish()
        #expect(total(result) == 900)
        #expect(result.aggregate.report.duplicatesDiscarded == 1)
        #expect(result.aggregate.report.events == 1)
    }

    @Test(
        "dobrar um arquivo em uma passagem e em duas, com corte em cada fronteira de linha, produz o mesmo agregado — reler um grupo substitui, nunca soma",
        arguments: 0...(Self.mixedFile.count)
    )
    func resumingIsIdempotentAtEveryLineBoundary(cut: Int) {
        let lines = Self.mixedFile
        let expected = total(foldAll(lines))
        #expect(expected == Self.mixedFileTotal, "a passagem única já divergiu do total conhecido")

        let firstPass = foldAll(Array(lines.prefix(cut)))
        let resume = ResumePolicy.resumePoint(afterFolding: rows(of: Array(lines.prefix(cut))))
        let resumeLine = Self.lineIndex(ofOffset: resume.offset, in: lines)

        var ledger = firstPass.ledger
        ledger.dropKeys(of: onlyFile, fromLine: resumeLine)

        var second = UsageFold(now: horizon, calendar: utc, carrying: ledger)
        second.noteFileRead()
        for index in resumeLine..<lines.count {
            second.absorb(
                lines[index].record,
                at: ScanPosition(fileOrdinal: 0, lineOrdinal: index),
                from: onlyFile
            )
        }

        let resumed = total(second.finish())
        #expect(resumed == expected, "corte na linha \(cut) divergiu")
    }

    @Test("o deslocamento retomado recua para o início do grupo da cauda, não para o fim do arquivo")
    func resumeOffsetRewindsToTheTailGroup() {
        let lines = [
            Line(key: "msg_a", accumulated: 10, bytes: 100),
            Line(key: "msg_b", accumulated: 20, bytes: 200),
            Line(key: "msg_b", accumulated: 30, bytes: 300),
            Line(key: "msg_b", accumulated: 40, bytes: 400)
        ]

        let point = ResumePolicy.resumePoint(afterFolding: rows(of: lines))

        #expect(point.tailKey == UsageKey(value: "msg_b", origin: .messageID))
        #expect(point.offset == 100)
    }

    @Test("sem nenhuma linha com chave, a retomada não recua para dentro do que já foi consumido")
    func resumeWithoutKeyedRowStaysAtTheEnd() {
        let unkeyed = [
            ScannedRow(key: nil, offset: 0, length: 50),
            ScannedRow(key: nil, offset: 50, length: 70)
        ]

        let point = ResumePolicy.resumePoint(afterFolding: unkeyed)

        #expect(point.offset == 120)
        #expect(point.tailKey == nil)
    }

    @Test("o relatório de cobertura tem os seis números e o primeiro e o último instante")
    func coverageReportCarriesSixNumbers() {
        var fold = UsageFold(now: horizon, calendar: utc)
        for _ in 0..<11 { fold.noteFileRead() }
        fold.noteFileUnread()

        for index in 0..<40 {
            let line = Line(key: "msg_\(index)", accumulated: 10, seconds: Double(index) * 60)
            fold.absorb(line.record, at: ScanPosition(fileOrdinal: 0, lineOrdinal: index), from: onlyFile)
        }
        for index in 0..<7 {
            let line = Line(key: "msg_\(index)", accumulated: 10, seconds: Double(index) * 60)
            fold.absorb(line.record, at: ScanPosition(fileOrdinal: 1, lineOrdinal: index), from: FileIdentity(digest: 2))
        }
        for index in 0..<3 {
            fold.absorb(unusable: .missingCounters, at: ScanPosition(fileOrdinal: 2, lineOrdinal: index))
        }

        let report = fold.finish().aggregate.report
        #expect(report.events == 40)
        #expect(report.filesRead == 11)
        #expect(report.filesUnread == 1)
        #expect(report.recordsIgnored == 3)
        #expect(report.duplicatesDiscarded == 7)
        #expect(report.earliestEventAt == epoch)
        #expect(report.latestEventAt == epoch.addingTimeInterval(39 * 60))
    }

    @Test("registro inválido não zera evento nem interrompe a leitura")
    func invalidRecordsDoNotZeroTheAggregate() {
        var fold = UsageFold(now: horizon, calendar: utc)
        fold.noteFileRead()

        for index in 0..<5 {
            let line = Line(key: "msg_\(index)", accumulated: 100)
            fold.absorb(line.record, at: ScanPosition(fileOrdinal: 0, lineOrdinal: index), from: onlyFile)
        }
        for (offset, reason) in [
            UnusableReason.missingCounters,
            .missingTimestamp,
            .missingModel,
            .undecodableLine
        ].enumerated() {
            fold.absorb(unusable: reason, at: ScanPosition(fileOrdinal: 0, lineOrdinal: 5 + offset))
        }

        let result = fold.finish()
        #expect(result.aggregate.report.events == 5)
        #expect(result.aggregate.report.recordsIgnored == 4)
        #expect(total(result) == 500)
        #expect(result.health.usable == 5)
        #expect(result.health.unrecognized == 4)
    }

    @Test("instante no futuro é ignorado e contado, e não entra em total algum")
    func futureRecordsAreRejected() {
        var fold = UsageFold(now: horizon, calendar: utc)
        fold.noteFileRead()
        fold.absorb(
            Line(key: "msg_now", accumulated: 100).record,
            at: ScanPosition(fileOrdinal: 0, lineOrdinal: 0),
            from: onlyFile
        )
        fold.absorb(
            Line(key: "msg_future", accumulated: 999, seconds: 2 * 86_400).record,
            at: ScanPosition(fileOrdinal: 0, lineOrdinal: 1),
            from: onlyFile
        )

        let result = fold.finish()
        #expect(total(result) == 100)
        #expect(result.aggregate.report.recordsIgnored == 1)
    }

    @Test("valor que diminui na ordem de escrita conta uma violação de monotonicidade")
    func decreasingValueCountsAsViolation() {
        let ascending = foldAll([Line(key: "k", accumulated: 10), Line(key: "k", accumulated: 20)])
        #expect(ascending.health.monotonicityViolations == 0)

        let descending = foldAll([Line(key: "k", accumulated: 20), Line(key: "k", accumulated: 10)])
        #expect(descending.health.monotonicityViolations == 1)
    }

    @Test("arquivo que sumiu deixa de contribuir e o total diminui")
    func vanishedFileStopsContributing() {
        var fold = UsageFold(now: horizon, calendar: utc)
        fold.noteFileRead()
        fold.noteFileRead()
        for index in 0..<28 {
            fold.absorb(
                Line(key: "kept_\(index)", accumulated: 10).record,
                at: ScanPosition(fileOrdinal: 0, lineOrdinal: index),
                from: FileIdentity(digest: 1)
            )
        }
        for index in 0..<12 {
            fold.absorb(
                Line(key: "gone_\(index)", accumulated: 10).record,
                at: ScanPosition(fileOrdinal: 1, lineOrdinal: index),
                from: FileIdentity(digest: 2)
            )
        }

        let before = fold.finish()
        #expect(before.aggregate.report.events == 40)

        var ledger = before.ledger
        ledger.dropKeys(outside: [FileIdentity(digest: 1)])

        var after = UsageFold(now: horizon, calendar: utc, carrying: ledger)
        after.noteFileRead()
        let result = after.finish()

        #expect(result.aggregate.report.events == 28)
        #expect(total(result) == 280)
    }

    private static let mixedFileTotal = 210 + 7 + 4_096 + 33

    private static let mixedFile: [Line] = {
        var lines = [Line(key: "msg_a", accumulated: 100), Line(key: "msg_a", accumulated: 180)]
        lines.append(Line(key: "msg_a", accumulated: 210))
        lines.append(Line(key: "msg_solo", accumulated: 7))
        lines += (1...24).map { Line(key: "msg_long", accumulated: $0 == 24 ? 4_096 : $0 * 50) }
        lines += [Line(key: "msg_tail", accumulated: 11), Line(key: "msg_tail", accumulated: 33)]
        return lines
    }()

    private static func lineIndex(ofOffset offset: Int64, in lines: [Line]) -> Int {
        var running: Int64 = 0
        for (index, line) in lines.enumerated() {
            if running == offset { return index }
            running += line.bytes
        }
        return lines.count
    }
}
