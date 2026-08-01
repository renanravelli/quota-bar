import Foundation
import Testing

private enum PackageLayout {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let manifest: String = {
        let text = try? String(contentsOf: root.appending(path: "Package.swift"), encoding: .utf8)
        return (text ?? "").filter { !$0.isWhitespace }
    }()

    static func targetDeclaration(named name: String) -> String? {
        let openers = [".target(name:\"\(name)\"", ".testTarget(name:\"\(name)\""]
        guard let start = openers.lazy.compactMap({ manifest.range(of: $0) }).first else { return nil }

        let rest = manifest[start.upperBound...]
        let nextTarget = [".target(", ".testTarget("]
            .compactMap { rest.range(of: $0)?.lowerBound }
            .min() ?? rest.endIndex

        return String(rest[..<nextTarget])
    }

    static func swiftSources(of target: String) -> [URL] {
        let directory = root.appending(path: "Sources").appending(path: target)
        let contents = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        return (contents?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }
    }
}

@Suite("Direção da dependência entre domínio e transporte")
struct DependencyDirectionTests {
    private static let domainTargets = ["QuotaBarCore", "QuotaBarCoreFixtures"]

    @Test("AC-25: o manifesto do domínio não declara dependência do transporte", arguments: domainTargets)
    func domainTargetDoesNotDependOnTransport(target: String) throws {
        let declaration = try #require(PackageLayout.targetDeclaration(named: target))

        #expect(!declaration.contains("QuotaBarTransport"))
    }

    @Test("AC-25: nenhum arquivo do domínio menciona o módulo da credencial", arguments: domainTargets)
    func noDomainSourceMentionsTransport(target: String) throws {
        let sources = PackageLayout.swiftSources(of: target)
        #expect(!sources.isEmpty, "nenhum arquivo encontrado em \(target)")

        for source in sources {
            let contents = try String(contentsOf: source, encoding: .utf8)
            #expect(!contents.contains("QuotaBarTransport"), "\(source.lastPathComponent) cita o transporte")
        }
    }

    @Test("AC-25: a dependência existe no sentido oposto, do transporte para o domínio")
    func transportDependsOnDomain() throws {
        let declaration = try #require(PackageLayout.targetDeclaration(named: "QuotaBarTransport"))

        #expect(declaration.contains("QuotaBarCore"))
    }

    @Test("AC-25: nenhuma API pública do domínio recebe a credencial como parâmetro")
    func noDomainAPITakesTheCredential() throws {
        for target in Self.domainTargets {
            for source in PackageLayout.swiftSources(of: target) {
                let contents = try String(contentsOf: source, encoding: .utf8)
                #expect(!contents.contains("SubscriptionToken"), "\(source.lastPathComponent) cita o portador")
                #expect(!contents.contains("CredentialStoring"), "\(source.lastPathComponent) cita o guarda")
            }
        }
    }
}
