import Foundation
import QuotaBarCore
import Testing

@testable import QuotaBarTransport

@Suite("Descoberta do Claude Code no sistema de arquivos")
struct SystemClaudeCodeEnvironmentTests {
    private static func makeHome() throws -> URL {
        let home = URL(filePath: NSTemporaryDirectory())
            .appending(path: "quotabar-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @discardableResult
    private static func installClaude(in home: URL, reporting version: String, linked: Bool = false) throws -> URL {
        let versions = home.appending(path: ".local/share/claude/versions")
        let bin = home.appending(path: ".local/bin")
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let executable = versions.appending(path: version)
        try "#!/bin/sh\necho '\(version) (Claude Code)'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let launcher = bin.appending(path: "claude")
        try? FileManager.default.removeItem(at: launcher)
        if linked {
            try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: executable)
        } else {
            try FileManager.default.copyItem(at: executable, to: launcher)
        }
        return launcher
    }

    @Test("o executável instalado é localizado e a versão vem de --version")
    func theInstalledExecutableReportsItsVersion() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Self.installClaude(in: home, reporting: "2.1.220")

        var resolver = ClaudeCodeVersionResolver(environment: SystemClaudeCodeEnvironment(home: home))

        #expect(resolver.resolve().version == "2.1.220")
    }

    @Test("sem Claude Code instalado, a descoberta devolve não encontrado")
    func withoutAnInstallationNothingIsDiscovered() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        var resolver = ClaudeCodeVersionResolver(environment: SystemClaudeCodeEnvironment(home: home))
        let discovery = resolver.resolve()

        #expect(discovery == .notFound)
        #expect(!discovery.allowsProbe)
    }

    @Test("o cache é revalidado pelo alvo do symlink, não pelo link")
    func theCacheIsKeyedOnTheResolvedTarget() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Self.installClaude(in: home, reporting: "2.1.220", linked: true)

        let environment = SystemClaudeCodeEnvironment(home: home)
        var resolver = ClaudeCodeVersionResolver(environment: environment)
        #expect(resolver.resolve().version == "2.1.220")

        try Self.installClaude(in: home, reporting: "2.2.0", linked: true)

        #expect(resolver.resolve().version == "2.2.0")
    }
}
