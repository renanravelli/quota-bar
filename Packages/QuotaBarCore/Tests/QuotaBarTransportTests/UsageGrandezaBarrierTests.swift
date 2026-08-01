import Foundation
import QuotaBarCore
import Testing

private enum SourceTree {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func source(_ target: String, _ file: String) throws -> String {
        try String(
            contentsOf: root.appending(path: "Sources").appending(path: target).appending(path: file),
            encoding: .utf8
        )
    }

    static let tokenSectionFiles = tokenBearingFiles + [
        "IngestionHealth.swift",
        "ResumePolicy.swift"
    ]

    static let tokenBearingFiles = [
        "TokenCounts.swift",
        "ModelIdentity.swift",
        "UsageRecord.swift",
        "UsageRecordFactory.swift",
        "UsageFold.swift",
        "UsageLedger.swift",
        "UsageAggregate.swift",
        "SeriesWindow.swift",
        "WorkBand.swift"
    ]

    static func sources(of target: String) throws -> [String: String] {
        let directory = root.appending(path: "Sources").appending(path: target)
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []

        return try files.reduce(into: [:]) { sources, file in
            sources[file.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
        }
    }
}

enum TokenBearingAudit {
    static func carryingTokenCounts(_ sources: [String: String]) -> [String] {
        sources.filter { $0.value.contains("TokenCounts") }.keys.sorted()
    }

    static func unlisted(_ sources: [String: String], listed: [String]) -> [String] {
        carryingTokenCounts(sources).filter { !listed.contains($0) }
    }
}

@Suite("A barreira entre a contagem de tokens e o percentual de cota")
struct UsageGrandezaBarrierTests {
    @Test("nenhum tipo da seção de tokens alcança `Utilization`", arguments: SourceTree.tokenSectionFiles)
    func tokenSectionNeverReachesUtilization(file: String) throws {
        let contents = try SourceTree.source("QuotaBarCore", file)

        #expect(!contents.contains("Utilization"), "\(file) alcança a grandeza de cota")
    }

    @Test(
        "nenhum tipo que carrega contagem de token expõe a fração de participação de um modelo",
        arguments: SourceTree.tokenBearingFiles
    )
    func participationHasNoCarrier(file: String) throws {
        let contents = try SourceTree.source("QuotaBarCore", file)

        for forbidden in ["participation", "share", "fraction", "percent"] {
            #expect(
                !contents.localizedCaseInsensitiveContains(forbidden),
                "\(file) carrega `\(forbidden)` — a razão é intermediário local, não campo"
            )
        }
    }

    @Test("a varredura enxerga os arquivos do domínio que de fato carregam contagem de token")
    func theSweepSeesTheFilesThatCarryTokenCounts() throws {
        let carrying = TokenBearingAudit.carryingTokenCounts(try SourceTree.sources(of: "QuotaBarCore"))

        #expect(
            Set(carrying).isSuperset(of: [
                "TokenCounts.swift",
                "UsageAggregate.swift",
                "UsageFold.swift",
                "UsageRecord.swift",
                "UsageRecordFactory.swift",
                "WorkBand.swift"
            ]),
            "a varredura não alcançou o domínio: \(carrying.joined(separator: ", "))"
        )
    }

    @Test("todo arquivo do domínio que carrega contagem de token está na lista do portão")
    func theListLeavesNoTokenBearingFileOut() throws {
        let unlisted = try TokenBearingAudit.unlisted(
            SourceTree.sources(of: "QuotaBarCore"),
            listed: SourceTree.tokenBearingFiles
        )

        #expect(unlisted.isEmpty, "fora da lista do portão: \(unlisted.joined(separator: ", "))")
    }

    @Test("um arquivo novo que carrega contagem de token e ficou fora da lista é acusado")
    func anUnlistedNewcomerIsCaught() {
        let sources = [
            "TokenCounts.swift": "public struct TokenCounts {}",
            "SemContagem.swift": "public enum SemContagem {}",
            "FaixaNova.swift": "func of(_ model: TokenCounts, inTotal: TokenCounts) -> Int { 0 }"
        ]

        #expect(TokenBearingAudit.unlisted(sources, listed: ["TokenCounts.swift"]) == ["FaixaNova.swift"])
        #expect(
            TokenBearingAudit.unlisted(sources, listed: ["TokenCounts.swift", "FaixaNova.swift"]).isEmpty
        )
    }

    @Test("`Utilization` não é construível a partir de `TokenCounts`")
    func utilizationIsNotConstructibleFromTokens() throws {
        let contents = try SourceTree.source("QuotaBarCore", "Utilization.swift")

        #expect(!contents.contains("TokenCounts"))
        #expect(!contents.contains("TokenTotal"))
    }

    @Test("o decodificador não tem campo onde receber conteúdo, caminho, ramo nem sessão")
    func decoderHasNoFieldForContentOrPath() throws {
        let contents = try SourceTree.source("QuotaBarTransport", "TranscriptLine.swift")

        for forbidden in ["content", "cwd", "gitBranch", "sessionId", "toolUseResult", "path"] {
            #expect(!contents.contains(forbidden), "o decodificador tem campo para `\(forbidden)`")
        }
    }

    @Test("nada derivado de caminho é persistido no índice")
    func indexPersistsNoPath() throws {
        let contents = try SourceTree.source("QuotaBarTransport", "UsageIndex.swift")

        #expect(!contents.contains("let path"))
        #expect(!contents.contains("case path"))
    }
}
