import Foundation
import QuotaBarCore
import Testing

@testable import QuotaBarTransport

final class TemporarySampleLog {
    let directory: URL
    let fileURL: URL
    let log: FileQuotaSampleLog

    init() {
        directory = URL.temporaryDirectory.appending(
            path: "quotabar-series-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        fileURL = directory.appending(path: "quota-series.json", directoryHint: .notDirectory)
        log = FileQuotaSampleLog(fileURL: fileURL)
    }

    var contents: Data? {
        try? Data(contentsOf: fileURL)
    }

    var text: String {
        contents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func write(_ raw: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(raw.utf8).write(to: fileURL, options: .atomic)
    }

    func growBeyondAnyHorizon(by seconds: Double) throws {
        guard let data = contents,
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var samples = root["samples"] as? [[String: Any]],
              var oldest = samples.first,
              let readAt = oldest["readAt"] as? Double
        else { throw SampleLogTestFailure.unreadablePersistedFile }

        oldest["readAt"] = readAt - seconds
        oldest["readSequence"] = 0
        samples.insert(oldest, at: 0)
        root["samples"] = samples

        try JSONSerialization.data(withJSONObject: root).write(to: fileURL, options: .atomic)
    }

    func reopened() -> FileQuotaSampleLog {
        FileQuotaSampleLog(fileURL: fileURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum SampleLogTestFailure: Error {
    case unreadablePersistedFile
}

private nonisolated(unsafe) let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

enum TestSample {
    static func instant(_ iso: String) -> Date {
        guard let date = isoFormatter.date(from: iso) else {
            fatalError("instante de teste inválido: \(iso)")
        }
        return date
    }

    static func percent(_ value: String) -> Utilization {
        guard let decimal = Decimal(string: value), let utilization = Utilization(originPercent: decimal) else {
            fatalError("percentual de teste inválido: \(value)")
        }
        return utilization
    }

    static func at(
        _ readAt: Date,
        sequence: UInt64,
        fiveHour: String? = "40.00",
        sevenDay: String? = "21.00",
        resetsAt: Date? = nil,
        source: QuotaSource = .primaryProbe
    ) -> QuotaSample {
        QuotaSample(
            readAt: readAt,
            readSequence: sequence,
            fiveHour: fiveHour.map(percent),
            sevenDay: sevenDay.map(percent),
            fiveHourResetsAt: resetsAt,
            sevenDayResetsAt: resetsAt,
            source: source
        )
    }

    static func at(
        _ iso: String,
        sequence: UInt64,
        fiveHour: String? = "40.00",
        sevenDay: String? = "21.00",
        source: QuotaSource = .primaryProbe
    ) -> QuotaSample {
        at(instant(iso), sequence: sequence, fiveHour: fiveHour, sevenDay: sevenDay, source: source)
    }
}

@Suite("Registro persistido da série de cota")
struct FileQuotaSampleLogTests {
    @Test("a série sobrevive ao encerramento e o intervalo sem execução permanece sem amostras")
    func theSeriesSurvivesRelaunchAndKeepsItsHole() async {
        let store = TemporarySampleLog()

        await store.log.append(TestSample.at("2026-08-01T09:30:00Z", sequence: 1))
        await store.log.append(TestSample.at("2026-08-01T10:00:00Z", sequence: 2))

        let relaunched = store.reopened()
        await relaunched.append(TestSample.at("2026-08-01T14:00:00Z", sequence: 3))
        let restored = await relaunched.load(since: TestSample.instant("2026-07-01T00:00:00Z"))

        #expect(restored.samples.map(\.readAt) == [
            TestSample.instant("2026-08-01T09:30:00Z"),
            TestSample.instant("2026-08-01T10:00:00Z"),
            TestSample.instant("2026-08-01T14:00:00Z")
        ])
        #expect(restored.restoration == .intact)
    }

    @Test("a amostra de identidade já registrada não é gravada duas vezes")
    func anAlreadyRegisteredReadingIsNotWrittenTwice() async {
        let store = TemporarySampleLog()
        let sample = TestSample.at("2026-08-01T09:30:00Z", sequence: 1)

        await store.log.append(sample)
        await store.log.append(sample)
        await store.log.append(sample)

        let restored = await store.log.load(since: .distantPast)
        #expect(restored.samples.count == 1)
    }

    @Test("a retenção de 14 dias descarta pela ponta antiga e nunca a amostra mais recente")
    func retentionDiscardsTheOldestAndKeepsTheNewest() async {
        let store = TemporarySampleLog()
        let now = TestSample.instant("2026-08-01T12:00:00Z")
        let expired = now.addingTimeInterval(-(14 * 24 * 3_600 + 60))
        let withinHorizon = now.addingTimeInterval(-(13 * 24 * 3_600))

        await store.log.append(TestSample.at(expired, sequence: 1))
        await store.log.append(TestSample.at(withinHorizon, sequence: 2))
        await store.log.append(TestSample.at(now, sequence: 3))

        let restored = await store.log.load(since: .distantPast)

        #expect(restored.samples.map(\.readSequence) == [2, 3])
        #expect(!restored.samples.contains { $0.readAt == expired })
    }

    @Test("a amostra exatamente no horizonte de 14 dias é retida, e um segundo além dele não é")
    func theSampleExactlyAtTheHorizonIsRetained() async {
        let store = TemporarySampleLog()
        let now = TestSample.instant("2026-08-01T12:00:00Z")
        let horizonInSeconds = 14.0 * 24 * 3_600

        await store.log.append(TestSample.at(now.addingTimeInterval(-(horizonInSeconds + 1)), sequence: 1))
        await store.log.append(TestSample.at(now.addingTimeInterval(-horizonInSeconds), sequence: 2))
        await store.log.append(TestSample.at(now, sequence: 3))

        let restored = await store.log.load(since: .distantPast)

        #expect(restored.samples.map(\.readSequence) == [2, 3])
    }

    @Test("um arquivo que cresceu além do horizonte é lido inteiro, e só a escrita seguinte o poda")
    func theReaderNeverHidesAFileThatGrewBeyondTheHorizon() async throws {
        let store = TemporarySampleLog()
        let now = TestSample.instant("2026-08-01T12:00:00Z")

        await store.log.append(TestSample.at(now, sequence: 1))
        try store.growBeyondAnyHorizon(by: 20 * 24 * 3_600)

        let asItStandsOnDisk = await store.log.load(since: .distantPast)

        await store.log.append(TestSample.at(now.addingTimeInterval(60), sequence: 2))
        let afterTheNextWrite = await store.log.load(since: .distantPast)

        #expect(asItStandsOnDisk.samples.map(\.readSequence) == [0, 1])
        #expect(afterTheNextWrite.samples.map(\.readSequence) == [1, 2])
    }

    @Test("a amostra mais recente sobrevive mesmo sendo a única e mais velha que o horizonte")
    func theNewestSampleIsNeverDiscarded() async {
        let store = TemporarySampleLog()
        let ancient = TestSample.instant("2020-01-01T00:00:00Z")

        await store.log.append(TestSample.at(ancient, sequence: 1))
        let restored = await store.log.load(since: .distantPast)

        #expect(restored.samples.map(\.readSequence) == [1])
    }

    @Test("série persistida corrompida é tratada como vazia, o fato é declarado e a gravação recomeça sem aproveitar metade")
    func anUnreadableSeriesRestartsWithoutSalvagingHalfOfIt() async {
        let store = TemporarySampleLog()

        await store.log.append(TestSample.at("2026-08-01T09:30:00Z", sequence: 1, fiveHour: "11.00"))
        await store.log.append(TestSample.at("2026-08-01T10:00:00Z", sequence: 2, fiveHour: "12.00"))

        let truncated = String(store.text.prefix(store.text.count / 2))
        store.write(truncated)

        let reopened = store.reopened()
        let corrupted = await reopened.load(since: .distantPast)

        #expect(corrupted.samples.isEmpty)
        #expect(corrupted.restoration == .restartedAfterUnreadableLog)

        await reopened.append(TestSample.at("2026-08-01T10:30:00Z", sequence: 3, fiveHour: "13.00"))
        let restarted = await reopened.load(since: .distantPast)

        #expect(restarted.samples.map(\.readSequence) == [3])
        #expect(restarted.restoration == .intact)
        #expect(!store.text.contains("1100"))
    }

    @Test("arquivo ausente é série vazia íntegra, e não série ilegível")
    func aMissingFileIsAnIntactEmptySeries() async {
        let store = TemporarySampleLog()

        let restored = await store.log.load(since: .distantPast)

        #expect(restored.samples.isEmpty)
        #expect(restored.restoration == .intact)
    }

    @Test("o conteúdo persistido tem só instante, percentuais, resets, fonte e identidade de leitura")
    func thePersistedContentCarriesNothingSensitive() async throws {
        let store = TemporarySampleLog()

        await store.log.append(TestSample.at("2026-08-01T09:30:00Z", sequence: 1))
        await store.log.append(TestSample.at("2026-08-01T10:00:00Z", sequence: 2, sevenDay: nil))

        let data = try #require(store.contents)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let samples = try #require(root["samples"] as? [[String: Any]])

        #expect(Set(root.keys) == ["version", "samples"])
        for sample in samples {
            #expect(
                Set(sample.keys).isSubset(of: [
                    "readAt",
                    "readSequence",
                    "fiveHourBasisPoints",
                    "sevenDayBasisPoints",
                    "fiveHourResetsAt",
                    "sevenDayResetsAt",
                    "source"
                ])
            )
        }

        let text = store.text.lowercased()
        for forbidden in ["token", "credential", "sk-ant", "account", "organization", "cwd", "project", "message"] {
            #expect(!text.contains(forbidden), "o conteúdo persistido menciona \(forbidden)")
        }
    }

    @Test("percentual ausente é gravado como ausente, e nunca como zero")
    func anAbsentUtilizationIsPersistedAsAbsent() async throws {
        let store = TemporarySampleLog()

        await store.log.append(TestSample.at("2026-08-01T09:30:00Z", sequence: 1, sevenDay: nil))
        let restored = await store.log.load(since: .distantPast)

        let sample = try #require(restored.samples.first)
        #expect(sample.sevenDay == nil)
        #expect(!store.text.contains("\"sevenDayBasisPoints\":0"))
    }

    @Test("o artefato da série é próprio, e não o slot de restauração da última leitura")
    func theSeriesArtefactIsItsOwnFile() async {
        let store = TemporarySampleLog()

        await store.log.append(TestSample.at("2026-08-01T09:30:00Z", sequence: 1))

        #expect(store.fileURL.lastPathComponent != "last-reading.json")
        #expect(store.text.contains("\"version\""))
    }

    @Test("o horizonte de retenção é de 14 dias")
    func theRetentionHorizonIsFourteenDays() {
        #expect(QuotaSampleRetention.horizon == .seconds(14 * 24 * 3_600))
    }
}
