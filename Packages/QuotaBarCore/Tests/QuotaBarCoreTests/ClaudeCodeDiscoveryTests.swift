import Foundation
import Testing

@testable import QuotaBarCore

private final class StubClaudeCodeEnvironment: ClaudeCodeEnvironment, @unchecked Sendable {
    private let lock = NSLock()
    private var executablesByCandidate: [ClaudeCodeCandidatePath: [ClaudeCodeExecutable]] = [:]
    private var outputByPath: [String: String] = [:]
    private var recordedLookups: [ClaudeCodeCandidatePath] = []
    private var recordedVersionReads: [String] = []

    var lookups: [ClaudeCodeCandidatePath] { lock.withLock { recordedLookups } }
    var versionReads: [String] { lock.withLock { recordedVersionReads } }

    func install(
        _ executable: ClaudeCodeExecutable,
        at candidate: ClaudeCodeCandidatePath,
        reporting output: String
    ) {
        lock.withLock {
            executablesByCandidate[candidate] = [executable]
            outputByPath[executable.path] = output
        }
    }

    func uninstallEverything() {
        lock.withLock { executablesByCandidate.removeAll() }
    }

    func executables(at candidate: ClaudeCodeCandidatePath) -> [ClaudeCodeExecutable] {
        lock.withLock {
            recordedLookups.append(candidate)
            return executablesByCandidate[candidate] ?? []
        }
    }

    func versionOutput(of executable: ClaudeCodeExecutable) -> String? {
        lock.withLock {
            recordedVersionReads.append(executable.path)
            return outputByPath[executable.path]
        }
    }
}

@Suite("Descoberta do Claude Code")
struct ClaudeCodeDiscoveryTests {
    private static let nativeInstaller = ClaudeCodeCandidatePath.userRelative(".local/bin/claude")
    private static let homebrew = ClaudeCodeCandidatePath.absolute("/opt/homebrew/bin/claude")

    private static func executable(
        path: String = "/Users/dev/.local/bin/claude",
        modifiedAt: TimeInterval = 1_700_000_000,
        size: Int = 42_000
    ) -> ClaudeCodeExecutable {
        ClaudeCodeExecutable(
            path: path,
            modifiedAt: Date(timeIntervalSince1970: modifiedAt),
            size: size
        )
    }

    @Test("a versão é apurada uma vez e reaproveitada nas leituras seguintes")
    func versionIsResolvedOnceAndReused() {
        let environment = StubClaudeCodeEnvironment()
        environment.install(Self.executable(), at: Self.nativeInstaller, reporting: "2.1.220 (Claude Code)")
        var resolver = ClaudeCodeVersionResolver(environment: environment)

        let discoveries = (1...3).map { _ in resolver.resolve() }

        #expect(discoveries.allSatisfy { $0.version == "2.1.220" })
        #expect(environment.versionReads.count == 1)
    }

    @Test("executável substituído reapura a versão sem reiniciar o aplicativo")
    func replacedExecutableIsReRead() {
        let environment = StubClaudeCodeEnvironment()
        environment.install(
            Self.executable(modifiedAt: 1_700_000_000, size: 42_000),
            at: Self.nativeInstaller,
            reporting: "2.1.220 (Claude Code)"
        )
        var resolver = ClaudeCodeVersionResolver(environment: environment)
        let before = resolver.resolve()

        environment.install(
            Self.executable(modifiedAt: 1_700_090_000, size: 43_500),
            at: Self.nativeInstaller,
            reporting: "2.2.0 (Claude Code)"
        )
        let after = resolver.resolve()

        #expect(before.version == "2.1.220")
        #expect(after.version == "2.2.0")
        #expect(environment.versionReads.count == 2)
    }

    @Test("sem Claude Code instalado não há versão nem leitura")
    func absentClaudeCodeBlocksProbing() {
        let environment = StubClaudeCodeEnvironment()
        var resolver = ClaudeCodeVersionResolver(environment: environment)

        let discovery = resolver.resolve()

        #expect(discovery == .notFound)
        #expect(discovery.version == nil)
        #expect(discovery.allowsProbe == false)
        #expect(environment.versionReads.isEmpty)
    }

    @Test("a busca percorre a lista fechada de caminhos candidatos e não consulta o PATH")
    func searchFollowsTheClosedList() {
        let environment = StubClaudeCodeEnvironment()
        var resolver = ClaudeCodeVersionResolver(environment: environment)

        _ = resolver.resolve()

        #expect(ClaudeCodeCandidatePath.ordered == [
            .userRelative(".local/bin/claude"),
            .userRelative(".claude/local/claude"),
            .absolute("/opt/homebrew/bin/claude"),
            .absolute("/usr/local/bin/claude"),
            .userRelative(".nvm/versions/node/*/bin/claude")
        ])
        #expect(environment.lookups == ClaudeCodeCandidatePath.ordered)
    }

    @Test("o primeiro caminho da lista vence e a busca para nele")
    func firstCandidateWins() {
        let environment = StubClaudeCodeEnvironment()
        environment.install(
            Self.executable(path: "/Users/dev/.local/bin/claude"),
            at: Self.nativeInstaller,
            reporting: "2.1.220 (Claude Code)"
        )
        environment.install(
            Self.executable(path: "/opt/homebrew/bin/claude"),
            at: Self.homebrew,
            reporting: "1.0.98 (Claude Code)"
        )
        var resolver = ClaudeCodeVersionResolver(environment: environment)

        let discovery = resolver.resolve()

        #expect(discovery.version == "2.1.220")
        #expect(environment.lookups == [Self.nativeInstaller])
    }

    @Test("saída irreconhecível não vira versão suposta")
    func unreadableOutputNeverBecomesAssumedVersion() {
        let environment = StubClaudeCodeEnvironment()
        environment.install(Self.executable(), at: Self.nativeInstaller, reporting: "unknown")
        var resolver = ClaudeCodeVersionResolver(environment: environment)

        let discovery = resolver.resolve()

        #expect(discovery == .notFound)
        #expect(discovery.allowsProbe == false)
    }

    @Test("Claude Code desinstalado em execução cessa a descoberta")
    func uninstalledDuringExecutionStopsDiscovery() {
        let environment = StubClaudeCodeEnvironment()
        environment.install(Self.executable(), at: Self.nativeInstaller, reporting: "2.1.220 (Claude Code)")
        var resolver = ClaudeCodeVersionResolver(environment: environment)
        _ = resolver.resolve()

        environment.uninstallEverything()
        let afterRemoval = resolver.resolve()

        environment.install(Self.executable(), at: Self.nativeInstaller, reporting: "2.1.220 (Claude Code)")
        let afterReinstall = resolver.resolve()

        #expect(afterRemoval == .notFound)
        #expect(afterReinstall.version == "2.1.220")
        #expect(environment.versionReads.count == 2)
    }

    @Test(
        "só a versão realmente lida é aceita",
        arguments: [
            ("2.1.220 (Claude Code)", "2.1.220"),
            ("  1.0.98 (Claude Code)\n", "1.0.98"),
            ("2.1.220", "2.1.220"),
            ("3.0.0-beta.4 (Claude Code)", "3.0.0-beta.4"),
            ("v2.1.220 (Claude Code)", nil),
            ("unknown", nil),
            ("2.1 (Claude Code)", nil),
            ("", nil)
        ] as [(String, String?)]
    )
    func versionParsingAcceptsOnlyWhatItRead(output: String, expected: String?) {
        #expect(ClaudeCodeVersion.parse(output) == expected)
    }
}
