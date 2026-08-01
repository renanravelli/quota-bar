import Foundation
import QuotaBarCore
import QuotaBarTransport

let assistedCanary = "sk-ant-oat01-CANARIO-DA-VIA-ASSISTIDA-QUE-NAO-PODE-VAZAR"

extension AssistedSetupOutcome {
    var acquiredToken: SubscriptionToken? {
        if case .obtained(let token) = self { return token }
        return nil
    }

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    var unavailability: AssistedSetupUnavailability? {
        if case .unavailable(let cause) = self { return cause }
        return nil
    }
}

extension ClaudeCodeDiscovery {
    static func stub(path: String = "/stub/claude") -> ClaudeCodeDiscovery {
        .installed(
            ClaudeCodeInstallation(
                version: "2.1.220",
                executable: ClaudeCodeExecutable(path: path, modifiedAt: .distantPast, size: 1)
            )
        )
    }
}

final class FakePseudoTerminalSession: PseudoTerminalSession, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [[UInt8]] = []
    private var isStreaming = true
    private var reader: CheckedContinuation<Void, Never>?
    private var written: [UInt8] = []
    private var status: Int32?
    private var terminations = 0

    var receivedBytes: [UInt8] { lock.withLock { written } }

    var receivedText: String { String(decoding: receivedBytes, as: UTF8.self) }

    var terminationCount: Int { lock.withLock { terminations } }

    func emit(_ bytes: [UInt8]) {
        wakeReader { pending.append(bytes) }
    }

    func emit(_ text: String) {
        emit(Array(text.utf8))
    }

    func endStream(status: Int32 = 0) {
        wakeReader {
            isStreaming = false
            self.status = status
        }
    }

    func readChunk(_ consume: (UnsafeRawBufferPointer) -> Void) async throws -> Bool {
        while true {
            let next: [UInt8]? = lock.withLock { pending.isEmpty ? nil : pending.removeFirst() }
            if let next {
                next.withUnsafeBytes(consume)
                return true
            }
            if lock.withLock({ !isStreaming }) || Task.isCancelled { return false }

            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let settled: Bool = lock.withLock {
                        guard pending.isEmpty, isStreaming, !Task.isCancelled else { return true }
                        reader = continuation
                        return false
                    }
                    if settled { continuation.resume() }
                }
            } onCancel: {
                wakeReader {}
            }
        }
    }

    func write(_ bytes: UnsafeRawBufferPointer) async throws {
        lock.withLock { written.append(contentsOf: bytes) }
    }

    func terminate() async {
        wakeReader {
            terminations += 1
            isStreaming = false
            if status == nil { status = 0 }
        }
    }

    func exitStatus() async -> Int32? {
        lock.withLock { status }
    }

    private func wakeReader(_ change: () -> Void) {
        let woken: CheckedContinuation<Void, Never>? = lock.withLock {
            change()
            defer { reader = nil }
            return reader
        }
        woken?.resume()
    }
}

final class FakePseudoTerminal: PseudoTerminalSpawning, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [TerminalCommand] = []
    private let failure: (any Error)?

    let session = FakePseudoTerminalSession()

    init(failingWith failure: (any Error)? = nil) {
        self.failure = failure
    }

    var spawnCount: Int { lock.withLock { commands.count } }

    var lastCommand: TerminalCommand? { lock.withLock { commands.last } }

    func spawn(_ command: TerminalCommand) throws -> any PseudoTerminalSession {
        if let failure { throw failure }
        lock.withLock { commands.append(command) }
        return session
    }
}

final class ManualClock: Clock, @unchecked Sendable {
    typealias Instant = ContinuousClock.Instant

    private let lock = NSLock()
    private let origin = ContinuousClock.now
    private var offset = Duration.zero
    private var sleepers: [(deadline: Instant, continuation: CheckedContinuation<Void, Never>)] = []

    var now: Instant { lock.withLock { origin + offset } }

    var minimumResolution: Duration { .zero }

    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let due: Bool = lock.withLock {
                guard origin + offset < deadline else { return true }
                sleepers.append((deadline, continuation))
                return false
            }
            if due { continuation.resume() }
        }
    }

    func advance(by delta: Duration) {
        let due: [CheckedContinuation<Void, Never>] = lock.withLock {
            offset += delta
            let reached = origin + offset
            let ready = sleepers.filter { $0.deadline <= reached }
            sleepers.removeAll { $0.deadline <= reached }
            return ready.map(\.continuation)
        }
        due.forEach { $0.resume() }
    }
}

enum Assisted {
    static func acquirer(
        discovery: ClaudeCodeDiscovery = .stub(),
        spawner: FakePseudoTerminal = FakePseudoTerminal(),
        clock: ManualClock = ManualClock(),
        timing: AssistedSetupTiming = .standard
    ) -> SetupTokenCredentialAcquirer<ManualClock> {
        SetupTokenCredentialAcquirer(
            discover: { discovery },
            spawner: spawner,
            home: URL(filePath: "/Users/quota-bar-test"),
            timing: timing,
            clock: clock
        )
    }

    static func settle(until reached: @Sendable () async -> Bool) async {
        for _ in 0..<10_000 where await !reached() {
            await Task.yield()
        }
    }

    static func frame(around token: String) -> String {
        "\u{1B}[2J\u{1B}[H\u{1B}[33m" + token + "\u{1B}[39m\r\n"
    }
}
