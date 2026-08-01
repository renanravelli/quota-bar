import Foundation
import QuotaBarCore
import Testing

@testable import QuotaBarTransport

final class TemporaryStore {
    let directory: URL
    let fileURL: URL
    let store: FileQuotaSnapshotStore

    init() {
        directory = URL.temporaryDirectory.appending(
            path: "quotabar-store-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        fileURL = directory.appending(path: "last-reading.json", directoryHint: .notDirectory)
        store = FileQuotaSnapshotStore(fileURL: fileURL)
    }

    var contents: Data? {
        try? Data(contentsOf: fileURL)
    }

    func write(_ data: Data) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    func fields() throws -> [String: Any] {
        guard let data = contents,
              let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw StoreTestFailure.unreadablePersistedFile }
        return fields
    }

    func rewriteFieldsOfPersistedFile(_ edit: (inout [String: Any]) -> Void) throws {
        var edited = try fields()
        edit(&edited)
        write(try JSONSerialization.data(withJSONObject: edited))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum StoreTestFailure: Error {
    case unreadablePersistedFile
}

private enum CycleVocabulary {
    static let names: Set<String> = [
        "cycle",
        "cycleId",
        "deferralDeadline",
        "cadence",
        "cadenceSeconds",
        "cadenceNature",
        "scheduledAt",
        "anchoredAt",
        "intended"
    ]
}

enum StoredReadingFixture {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)

    static func snapshot(
        fiveHourStatus: WindowStatus = .allowed,
        sevenDayStatus: WindowStatus = .allowedWarning,
        overallStatus: WindowStatus = .rejected,
        bindingWindow: BindingWindow = .window(.fiveHour),
        source: QuotaSource = .primaryProbe,
        readSequence: UInt64 = 7,
        readAt: Date = StoredReadingFixture.readAt
    ) -> QuotaSnapshot {
        QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: Utilization(originPercent: 78),
                resetsAt: readAt.addingTimeInterval(3_600),
                status: fiveHourStatus
            ),
            sevenDay: WindowReading(
                utilization: Utilization(originPercent: 41),
                resetsAt: readAt.addingTimeInterval(86_400),
                status: sevenDayStatus
            ),
            overallStatus: overallStatus,
            nextResetAt: readAt.addingTimeInterval(3_600),
            bindingWindow: bindingWindow,
            fallbackPercentage: Utilization(originPercent: 12),
            overage: OverageInfo(status: "enabled", disabledReason: "none"),
            readSequence: readSequence,
            readAt: readAt,
            source: source
        )!
    }
}

@Suite("Guarda do último estado de cota em arquivo")
struct FileQuotaSnapshotStoreTests {
    @Test("a leitura gravada volta idêntica, com o instante original")
    func aPersistedReadingComesBackIdentical() async throws {
        let temporary = TemporaryStore()
        let original = StoredReadingFixture.snapshot()

        await temporary.store.persist(original)
        let restored = try #require(await temporary.store.restore())

        #expect(restored == original)
        #expect(restored.readAt == StoredReadingFixture.readAt)
        #expect(restored.readSequence == 7)
    }

    @Test("a idade do estado restaurado é a real, medida do instante original")
    func theRestoredAgeIsTheRealOne() async throws {
        let temporary = TemporaryStore()
        let elapsed: TimeInterval = 11 * 60

        await temporary.store.persist(StoredReadingFixture.snapshot())
        let restored = try #require(await temporary.store.restore())

        let age = StalenessPolicy.age(
            ofReadingAt: restored.readAt,
            now: StoredReadingFixture.readAt.addingTimeInterval(elapsed)
        )
        #expect(age == .seconds(elapsed))
    }

    @Test(
        "o vocabulário da origem sobrevive à ida e à volta",
        arguments: [
            WindowStatus.allowed,
            .allowedWarning,
            .rejected,
            .unknown("degraded_by_origin")
        ]
    )
    func theOriginVocabularySurvivesTheRoundTrip(status: WindowStatus) async throws {
        let temporary = TemporaryStore()
        let original = StoredReadingFixture.snapshot(fiveHourStatus: status, overallStatus: status)

        await temporary.store.persist(original)
        let restored = try #require(await temporary.store.restore())

        #expect(restored.fiveHour.status == status)
        #expect(restored.overallStatus == status)
    }

    @Test(
        "janela limitante e fonte sobrevivem à ida e à volta",
        arguments: [
            BindingWindow.window(.fiveHour),
            .window(.sevenDay),
            .unrecognized("monthly")
        ]
    )
    func theBindingWindowSurvivesTheRoundTrip(bindingWindow: BindingWindow) async throws {
        let temporary = TemporaryStore()
        let original = StoredReadingFixture.snapshot(
            bindingWindow: bindingWindow,
            source: .contingencyStatusLine
        )

        await temporary.store.persist(original)
        let restored = try #require(await temporary.store.restore())

        #expect(restored.bindingWindow == bindingWindow)
        #expect(restored.source == .contingencyStatusLine)
    }

    @Test("arquivo ausente não é estado restaurado nem falha")
    func anAbsentFileRestoresNothing() async {
        let temporary = TemporaryStore()

        #expect(await temporary.store.restore() == nil)
    }

    @Test("conteúdo ilegível é descartado inteiro, e a guarda segue utilizável")
    func illegibleContentIsDiscardedWhole() async throws {
        let temporary = TemporaryStore()
        temporary.write(Data([0x00, 0xFF, 0x10, 0x42, 0x00]))

        #expect(await temporary.store.restore() == nil)

        let snapshot = StoredReadingFixture.snapshot()
        await temporary.store.persist(snapshot)
        #expect(await temporary.store.restore() == snapshot)
    }

    @Test("arquivo truncado é descartado inteiro")
    func aTruncatedFileIsDiscardedWhole() async throws {
        let temporary = TemporaryStore()
        await temporary.store.persist(StoredReadingFixture.snapshot())

        let complete = try #require(temporary.contents)
        temporary.write(complete.prefix(complete.count / 2))

        #expect(await temporary.store.restore() == nil)
    }

    @Test("versão futura é descartada inteira, sem interpretação parcial")
    func aFutureVersionIsDiscardedWhole() async throws {
        let temporary = TemporaryStore()
        await temporary.store.persist(StoredReadingFixture.snapshot())

        try temporary.rewriteFieldsOfPersistedFile { $0["version"] = 99 }

        #expect(await temporary.store.restore() == nil)
    }

    @Test("campo fora do domínio válido descarta o arquivo, em vez de virar leitura com zeros")
    func anOutOfRangeFieldDiscardsTheWholeFile() async throws {
        let temporary = TemporaryStore()
        await temporary.store.persist(StoredReadingFixture.snapshot())

        try temporary.rewriteFieldsOfPersistedFile { fields in
            var window = fields["fiveHour"] as? [String: Any] ?? [:]
            window["utilizationBasisPoints"] = -1
            fields["fiveHour"] = window
        }

        #expect(await temporary.store.restore() == nil)
    }

    @Test("fonte desconhecida descarta o arquivo, em vez de ser adivinhada")
    func anUnknownSourceDiscardsTheWholeFile() async throws {
        let temporary = TemporaryStore()
        await temporary.store.persist(StoredReadingFixture.snapshot())

        try temporary.rewriteFieldsOfPersistedFile { $0["source"] = "carrier_pigeon" }

        #expect(await temporary.store.restore() == nil)
    }

    @Test("o arquivo gravado tem exatamente os campos de cota, e nenhum outro")
    func theWrittenFileCarriesQuotaFieldsOnly() async throws {
        let temporary = TemporaryStore()
        await temporary.store.persist(StoredReadingFixture.snapshot())

        let fields = try temporary.fields()

        #expect(Set(fields.keys) == [
            "version",
            "fiveHour",
            "sevenDay",
            "overallStatus",
            "nextResetAt",
            "bindingWindow",
            "fallbackPercentageBasisPoints",
            "overageStatus",
            "overageDisabledReason",
            "readSequence",
            "readAt",
            "source"
        ])

        for name in ["fiveHour", "sevenDay"] {
            let window = try #require(fields[name] as? [String: Any])
            #expect(Set(window.keys) == ["utilizationBasisPoints", "resetsAt", "status"])
        }
    }

    @Test("o ciclo não integra o que se grava, e um ciclo no arquivo não é lido")
    func theCycleIsNeitherWrittenNorRead() async throws {
        let temporary = TemporaryStore()
        let original = StoredReadingFixture.snapshot()
        await temporary.store.persist(original)

        #expect(Set(try temporary.fields().keys).isDisjoint(with: CycleVocabulary.names))

        try temporary.rewriteFieldsOfPersistedFile { fields in
            fields["cycleId"] = 9
            fields["deferralDeadline"] = StoredReadingFixture.readAt.addingTimeInterval(270).timeIntervalSinceReferenceDate
            fields["cadenceSeconds"] = 180
        }

        #expect(await temporary.store.restore() == original)
    }
}
