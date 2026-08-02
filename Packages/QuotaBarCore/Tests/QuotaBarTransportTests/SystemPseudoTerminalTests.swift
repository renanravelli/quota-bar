import Darwin
import Foundation
import QuotaBarCore
import Testing

@testable import QuotaBarTransport

extension TerminalCommand {
    static func harness(_ executable: String, _ arguments: [String] = []) -> TerminalCommand {
        TerminalCommand(
            executable: URL(filePath: executable),
            arguments: arguments,
            environment: [
                "HOME": NSHomeDirectory(),
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "TERM": "xterm-256color",
                "LANG": "en_US.UTF-8"
            ],
            workingDirectory: URL(filePath: NSHomeDirectory()),
            window: .wide
        )
    }
}

extension String {
    var terminalFlags: Set<String> {
        Set(split(whereSeparator: \.isWhitespace).map(String.init))
    }
}

extension PseudoTerminalSession {
    func drain() async -> String {
        var text = ""
        while let more = try? await readChunk({ text += String(decoding: $0, as: UTF8.self) }), more {}
        return text
    }

    func readBytes(until terminator: UInt8, atMost rounds: Int = 8) async -> [UInt8] {
        var received: [UInt8] = []
        for _ in 0..<rounds where !received.contains(terminator) {
            guard let more = try? await readChunk({ received.append(contentsOf: $0) }), more else { break }
        }
        return received
    }
}

struct ScriptedPseudoTerminal: PseudoTerminalSpawning {
    let arguments: [String]

    func spawn(_ command: TerminalCommand) throws -> any PseudoTerminalSession {
        try SystemPseudoTerminal().spawn(
            TerminalCommand(
                executable: command.executable,
                arguments: arguments,
                environment: command.environment,
                workingDirectory: URL(filePath: NSHomeDirectory()),
                window: command.window
            )
        )
    }
}

@Suite("Pseudoterminal do sistema, com filhos que não autenticam", .serialized, .timeLimit(.minutes(1)))
struct SystemPseudoTerminalTests {
    @Test("o filho recebe um terminal de verdade, não um cano")
    func theChildGetsARealTerminal() async throws {
        let session = try SystemPseudoTerminal().spawn(.harness("/usr/bin/tty"))

        let reported = await session.drain()
        await session.terminate()

        #expect(reported.contains("/dev/ttys"))
        #expect(!reported.contains("not a tty"))
        #expect(await session.exitStatus() == 0)
    }

    @Test("a janela chega ao filho com 512 colunas, e o eco chega desligado")
    func theWindowIsWideAndTheEchoIsAlreadyOff() async throws {
        let session = try SystemPseudoTerminal().spawn(.harness("/bin/stty", ["-a"]))

        let reported = await session.drain()
        await session.terminate()

        let flags = reported.terminalFlags
        #expect(reported.contains("512 columns"))
        #expect(reported.contains("200 rows"))
        #expect(flags.contains("-echo"), "o eco chegou ligado ao filho: \(reported)")
        #expect(!flags.contains("echo"))
        #expect(flags.contains("-icanon"))
    }

    @Test("o percurso inteiro extrai um token fabricado de um pseudoterminal real, sem autenticar nada")
    func theWholePathExtractsAFabricatedTokenFromARealTerminal() async {
        let acquirer = SetupTokenCredentialAcquirer(
            discover: { .stub(path: "/bin/sh") },
            spawner: ScriptedPseudoTerminal(
                arguments: ["-c", "printf '\\033[2J\\033[33m%s\\033[39m\\r\\n' '\(assistedCanary)'"]
            )
        )

        let outcome = await acquirer.acquire { _ in }

        #expect(outcome.acquiredToken?.withValue { $0 } == assistedCanary)
    }

    @Test("saída não nula de um filho real vira recusa por política, e o texto dele não sobrevive ao desfecho")
    func aRealNonZeroExitBecomesAPolicyRefusal() async {
        let acquirer = SetupTokenCredentialAcquirer(
            discover: { .stub(path: "/bin/sh") },
            spawner: ScriptedPseudoTerminal(
                arguments: ["-c", "printf 'this policy does not permit\\r\\n' >&2; exit 1"]
            )
        )

        let outcome = await acquirer.acquire { _ in }

        #expect(outcome.unavailability == .refusedByPolicy)
        #expect(Mirror(reflecting: AssistedSetupUnavailability.refusedByPolicy).children.isEmpty)
    }

    @Test("o que escrevemos atravessa o pseudoterminal e chega ao filho, aparado e com um retorno")
    func whatWeWriteReachesTheChild() async throws {
        let session = try SystemPseudoTerminal().spawn(.harness("/bin/cat"))
        let code = "abc123XYZ#estado-da-autorizacao"
        let outbox = SecretOutbox()

        try await session.write(outbox.load(code, terminatedBy: 0x0D))
        outbox.wipe()
        let echoed = await session.readBytes(until: 0x0D)
        await session.terminate()

        #expect(echoed.starts(with: Array(code.utf8) + [0x0D]))
        #expect(echoed.filter { $0 == 0x0D }.count == 1)
        #expect(outbox.isZeroed)
    }

    @Test("o filho que não termina sozinho é encerrado e reapeado, sem deixar órfão nem zumbi")
    func aChildThatNeverEndsIsTerminatedAndReaped() async throws {
        let session = try #require(
            SystemPseudoTerminal().spawn(.harness("/bin/cat")) as? SystemPseudoTerminalSession
        )
        let child = session.processIdentifier

        #expect(kill(child, 0) == 0)

        await session.terminate()
        await session.terminate()

        #expect(kill(child, 0) == -1)
        #expect(errno == ESRCH)
        #expect(await session.exitStatus() != nil)
    }

    @Test("encerrar sessões cujo filho já terminou, em disputa, não derruba o processo")
    func closingSessionsWhoseChildAlreadyEndedNeverBringsTheProcessDown() async {
        let closures = 800
        let inFlight = 16

        await withTaskGroup(of: Int32?.self) { group in
            for index in 0..<closures {
                if index >= inFlight, let status = await group.next() { #expect(status == 0) }
                group.addTask { await Self.statusOfOneSpawnDrainedAndClosed() }
            }
            for await status in group { #expect(status == 0) }
        }
    }

    private static func statusOfOneSpawnDrainedAndClosed() async -> Int32? {
        guard let session = try? SystemPseudoTerminal().spawn(.harness("/usr/bin/true")) else { return nil }

        _ = await session.drain()
        await session.terminate()

        return await session.exitStatus()
    }

    @Test("o que o filho imprime antes de terminar chega inteiro, mesmo com sessões em disputa")
    func whatTheChildPrintsBeforeEndingArrivesWholeEvenUnderContention() async throws {
        let sessions = 6_400
        let inFlight = 32
        var silent = 0

        try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<sessions {
                if index >= inFlight, try await group.next() == false { silent += 1 }
                group.addTask { try await Self.oneSessionSawWhatTheChildPrinted() }
            }
            for try await heard in group where !heard { silent += 1 }
        }

        #expect(silent == 0, "\(silent) de \(sessions) sessões perderam a saída do filho")
    }

    private static func oneSessionSawWhatTheChildPrinted() async throws -> Bool {
        let session = try SystemPseudoTerminal().spawn(.harness("/bin/echo", ["ok"]))

        let heard = await session.drain()
        await session.terminate()

        return heard.contains("ok")
    }

    @Test("o encerramento chega ao filho como sinal, não como fim de fluxo")
    func theTerminationReachesTheChildAsASignal() async throws {
        let session = try SystemPseudoTerminal().spawn(.harness("/bin/cat"))

        await session.terminate()

        #expect(await session.exitStatus() == SIGTERM, "o filho terminou sem receber o sinal")
    }
}
