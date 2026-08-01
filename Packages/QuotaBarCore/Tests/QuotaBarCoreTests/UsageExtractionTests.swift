import Foundation
import Testing
@testable import QuotaBarCore

private let instant = Date(timeIntervalSince1970: 1_780_000_000)

private func usage(
    input: Int? = nil,
    output: Int? = nil,
    cacheRead: Int? = nil,
    cacheCreation: Int? = nil,
    malformed: [String] = []
) -> RawUsage {
    RawUsage(
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheCreation: cacheCreation,
        malformedCounters: malformed
    )
}

@Suite("Extração de eventos de uso")
struct UsageExtractionTests {
    @Test("um registro com uso vira um evento com os quatro contadores preservados")
    func singleRecordKeepsFourCountersApart() throws {
        let made = UsageRecordFactory.make(
            key: UsageKey(value: "msg_1", origin: .messageID),
            occurredAt: instant,
            model: "claude-opus-5",
            topLevel: usage(input: 100, output: 200, cacheRead: 400, cacheCreation: 300),
            iterations: []
        )

        let record = try #require(try? made.get())
        #expect(record.contributions.count == 1)

        let counts = try #require(record.contributions.first?.counts)
        #expect(counts.input == 100)
        #expect(counts.output == 200)
        #expect(counts.cacheCreation == 300)
        #expect(counts.cacheRead == 400)
    }

    @Test("o total declara quais contadores agrega, e os quatro seguem disponíveis")
    func totalDeclaresWhatItAggregates() {
        let counts = TokenCounts(input: 100, output: 200, cacheRead: 400, cacheCreation: 300)

        #expect(counts.total.value == 1_000)
        #expect(counts.total.aggregates == Set(TokenCounter.allCases))
        #expect(TokenCounter.allCases.map { counts[$0] } == [100, 200, 400, 300])
    }

    @Test("um registro repartido entre dois modelos vira dois eventos, sem trocar tokens de dono")
    func twoModelRecordProducesTwoEvents() throws {
        let fable = usage(input: 2, output: 4, cacheRead: 20_513, cacheCreation: 9_136)
        let opus = usage(input: 2, output: 2_609, cacheRead: 9_389, cacheCreation: 0)

        let made = UsageRecordFactory.make(
            key: UsageKey(value: "msg_fallback", origin: .messageID),
            occurredAt: instant,
            model: "claude-opus-4-8",
            topLevel: opus,
            iterations: [
                RawIteration(model: "claude-fable-5", usage: fable),
                RawIteration(model: "claude-opus-4-8", usage: opus)
            ]
        )

        let record = try #require(try? made.get())
        #expect(record.contributions.count == 2)
        #expect(record.counts.total.value == 41_655)

        let byModel = Dictionary(
            uniqueKeysWithValues: record.contributions.map { ($0.model, $0.counts.total.value) }
        )
        #expect(byModel[.model("claude-fable-5")] == 29_655)
        #expect(byModel[.model("claude-opus-4-8")] == 12_000)
    }

    @Test("iteração sem modelo herda o modelo do registro")
    func iterationInheritsRecordModel() throws {
        let made = UsageRecordFactory.make(
            key: UsageKey(value: "msg_single_iteration", origin: .messageID),
            occurredAt: instant,
            model: "claude-opus-5",
            topLevel: usage(input: 1, output: 2, cacheRead: 3, cacheCreation: 4),
            iterations: [RawIteration(model: nil, usage: usage(input: 1, output: 2, cacheRead: 3, cacheCreation: 4))]
        )

        let record = try #require(try? made.get())
        #expect(record.contributions.map(\.model) == [.model("claude-opus-5")])
    }

    @Test("com iterações, o bloco de topo não é somado por cima")
    func topLevelIsNotAddedWhenIterationsExist() throws {
        let parcel = usage(input: 1, output: 1, cacheRead: 1, cacheCreation: 1)
        let made = UsageRecordFactory.make(
            key: UsageKey(value: "msg_iterations", origin: .messageID),
            occurredAt: instant,
            model: "claude-opus-5",
            topLevel: usage(input: 500, output: 500, cacheRead: 500, cacheCreation: 500),
            iterations: [RawIteration(model: nil, usage: parcel)]
        )

        let record = try #require(try? made.get())
        #expect(record.counts.total.value == 4)
    }

    @Test("a identidade segue ordem de preferência, e sem nenhuma das três o registro é ignorado")
    func identityFollowsPreferenceOrder() throws {
        let complete = UsageKey(messageID: "msg", requestID: "req", uuid: "uid")
        #expect(complete == UsageKey(value: "msg", origin: .messageID))

        let withoutMessage = UsageKey(messageID: nil, requestID: "req", uuid: "uid")
        #expect(withoutMessage == UsageKey(value: "req", origin: .requestID))

        let onlyUUID = UsageKey(messageID: nil, requestID: nil, uuid: "uid")
        #expect(onlyUUID == UsageKey(value: "uid", origin: .uuid))

        #expect(UsageKey(messageID: nil, requestID: nil, uuid: nil) == nil)

        let ignored = UsageRecordFactory.make(
            key: nil,
            occurredAt: instant,
            model: "claude-opus-5",
            topLevel: usage(input: 1),
            iterations: []
        )
        #expect(throws: UnusableReason.missingKey) { try ignored.get() }
    }

    @Test(
        "cada campo ausente do núcleo mínimo produz o motivo próprio",
        arguments: [
            (UsageKey(value: "k", origin: .messageID), instant, "m", usage(), UnusableReason.missingCounters),
            (UsageKey(value: "k", origin: .messageID), nil, "m", usage(input: 1), .missingTimestamp),
            (UsageKey(value: "k", origin: .messageID), instant, nil, usage(input: 1), .missingModel),
            (nil, instant, "m", usage(input: 1), .missingKey),
            (UsageKey(value: "k", origin: .messageID), instant, "m", usage(input: -1), .negativeCounter),
            (
                UsageKey(value: "k", origin: .messageID),
                instant,
                "m",
                usage(input: 1, malformed: ["output_tokens"]),
                .malformedCounter("output_tokens")
            )
        ] as [(UsageKey?, Date?, String?, RawUsage, UnusableReason)]
    )
    func minimumCoreFailuresAreNamed(
        key: UsageKey?,
        occurredAt: Date?,
        model: String?,
        raw: RawUsage,
        expected: UnusableReason
    ) {
        let made = UsageRecordFactory.make(
            key: key,
            occurredAt: occurredAt,
            model: model,
            topLevel: raw,
            iterations: []
        )

        #expect(throws: expected) { try made.get() }
    }

    @Test("identificador desconhecido é preservado como registrado, e o não-modelo tem categoria própria")
    func unknownIdentifiersArePreserved() {
        #expect(ModelIdentity(recorded: "claude-modelo-que-ninguem-conhece")
            == .model("claude-modelo-que-ninguem-conhece"))
        #expect(ModelIdentity(recorded: "<synthetic>") == .nonModel("<synthetic>"))

        #expect(ModelIdentity(recorded: "claude-opus-5").recordedIdentifier == "claude-opus-5")
        #expect(ModelIdentity(recorded: "<synthetic>").namesAModel == false)
        #expect(ModelIdentity(recorded: "claude-opus-5").namesAModel)
    }

    @Test("modelos distintos da mesma família nunca são fundidos")
    func distinctModelsAreNeverMerged() {
        #expect(ModelIdentity(recorded: "claude-opus-5") != ModelIdentity(recorded: "claude-opus-4-8"))
        #expect(ModelIdentity(recorded: "claude-opus-4-6") != ModelIdentity(recorded: "claude-opus-4-8"))
    }
}
