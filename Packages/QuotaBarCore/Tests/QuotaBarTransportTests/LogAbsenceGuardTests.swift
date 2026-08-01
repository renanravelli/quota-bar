import Foundation
import Testing

private enum Repository {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let productionSources: [URL] = ["App/Sources", "Packages/QuotaBarCore/Sources"]
        .flatMap { swiftSources(under: root.appending(path: $0)) }

    static var configurationScopedSources: Set<String> {
        var names: Set<String> = []
        var collecting = false

        for line in manifestLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let declaration = trimmed.range(of: "EXCLUDED_SOURCE_FILE_NAMES:") {
                let inline = trimmed[declaration.upperBound...].trimmingCharacters(in: .whitespaces)
                collecting = inline.isEmpty
                if !inline.isEmpty { names.insert(inline) }
            } else if collecting, trimmed.hasPrefix("- ") {
                names.insert(String(trimmed.dropFirst(2)))
            } else {
                collecting = false
            }
        }

        return names
    }

    private static let manifestLines: [String] = {
        let text = (try? String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)) ?? ""
        return text.components(separatedBy: .newlines)
    }()

    private static func swiftSources(under directory: URL) -> [URL] {
        let contents = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        return (contents?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }
    }
}

@Suite("Ausência de log e independência de configuração")
struct LogAbsenceGuardTests {
    private static let loggingAPIs = ["os_log", "OSLog", "Logger(", "NSLog", "print(", "debugPrint", "dump("]

    private static let sourcesOnlyOneConfigurationCompiles: Set<String> = [
        "DebugProviderFactory.swift",
        "ReleaseProviderFactory.swift",
        "DevAssets.xcassets"
    ]

    private static let sourcesTheSweepMustReach: Set<String> = [
        "DebugProviderFactory.swift",
        "ReleaseProviderFactory.swift",
        "SubscriptionToken.swift",
        "KeychainCredentialStore.swift",
        "ResponseClassifier.swift",
        "QuotaState.swift",
        "SetupTokenScanner.swift",
        "SystemPseudoTerminal.swift",
        "SetupTokenCredentialAcquirer.swift",
        "SecretBuffer.swift",
        "CredentialSetupModel.swift",
        "CredentialSetupView.swift"
    ]

    private static let toolsTheSecretPathMustNotUse = ["/usr/bin/script", "SuspendingClock", "NSTemporaryDirectory"]

    @Test("QB-SEC-001 AC-21 e QB-API-001 AC-26: a varredura alcança as fontes das duas configurações")
    func theSweepReachesTheSourcesOfBothConfigurations() {
        let scanned = Set(Repository.productionSources.map(\.lastPathComponent))
        let missing = Self.sourcesTheSweepMustReach.subtracting(scanned)

        #expect(missing.isEmpty, "a varredura não alcançou \(missing.sorted().joined(separator: ", "))")
    }

    @Test("ADR-003 e QB-API-001 REQ-17: nenhuma fonte de produção registra em log")
    func noProductionSourceLogsAnything() throws {
        for source in Repository.productionSources {
            let contents = try String(contentsOf: source, encoding: .utf8)
            let used = Self.loggingAPIs.filter(contents.contains)

            #expect(used.isEmpty, "\(source.lastPathComponent) usa \(used.joined(separator: ", "))")
        }
    }

    @Test("QB-SEC-001 AC-21 e QB-API-001 AC-26: nenhuma fonte de produção compila condicionalmente")
    func noProductionSourceCompilesConditionally() throws {
        for source in Repository.productionSources {
            let compilesConditionally = try String(contentsOf: source, encoding: .utf8).contains("#if")

            #expect(!compilesConditionally, "\(source.lastPathComponent) compila condicionalmente")
        }
    }

    @Test("o percurso do segredo não usa gravador de sessão, disco temporário nem relógio que pausa com a máquina")
    func theSecretPathUsesNeitherFileWritersNorASuspendingClock() throws {
        for source in Repository.productionSources {
            let contents = try String(contentsOf: source, encoding: .utf8)
            let used = Self.toolsTheSecretPathMustNotUse.filter(contents.contains)

            #expect(used.isEmpty, "\(source.lastPathComponent) usa \(used.joined(separator: ", "))")
        }
    }

    @Test("QB-SEC-001 AC-21 e QB-API-001 AC-26: só o provedor difere entre Debug e Release")
    func onlyTheProviderDiffersBetweenConfigurations() {
        #expect(Repository.configurationScopedSources == Self.sourcesOnlyOneConfigurationCompiles)
    }
}
