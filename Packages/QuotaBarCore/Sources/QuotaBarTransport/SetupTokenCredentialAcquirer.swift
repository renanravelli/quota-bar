import Foundation
import QuotaBarCore

public actor SetupTokenCredentialAcquirer<Timeline: Clock>: AssistedCredentialAcquiring
where Timeline.Duration == Duration {
    private struct Conduction {
        let session: any PseudoTerminalSession
        let startedAt: Timeline.Instant
        var sawOutput = false
    }

    private static var carriageReturn: UInt8 { 0x0D }

    private let discover: @Sendable () async -> ClaudeCodeDiscovery
    private let spawner: any PseudoTerminalSpawning
    private let home: URL
    private let timing: AssistedSetupTiming
    private let clock: Timeline
    private let outbox = SecretOutbox()

    private var conduction: Conduction?
    private var expiry: AssistedSetupUnavailability?

    public init(
        discover: @escaping @Sendable () async -> ClaudeCodeDiscovery,
        spawner: any PseudoTerminalSpawning,
        home: URL = URL(filePath: NSHomeDirectory()),
        timing: AssistedSetupTiming = .standard,
        clock: Timeline
    ) {
        self.discover = discover
        self.spawner = spawner
        self.home = home
        self.timing = timing
        self.clock = clock
    }

    public func acquire(
        onProgress: @escaping @Sendable (AssistedSetupProgress) -> Void
    ) async -> AssistedSetupOutcome {
        guard conduction == nil else { return .cancelled }
        guard case .installed(let installation) = await discover() else {
            return .unavailable(.claudeCodeNotFound)
        }

        onProgress(.launching)

        let session: any PseudoTerminalSession
        do {
            session = try spawner.spawn(
                .setupToken(claudeCode: URL(filePath: installation.executable.path), home: home)
            )
        } catch {
            return .unavailable(.launchFailed)
        }

        expiry = nil
        conduction = Conduction(session: session, startedAt: clock.now)

        let watcher = Task { await self.enforceDeadlines(on: session) }
        let outcome = await withTaskCancellationHandler {
            await read(from: session, onProgress: onProgress)
        } onCancel: {
            Task { await session.terminate() }
        }

        watcher.cancel()
        await session.terminate()
        conduction = nil

        return outcome
    }

    public func submit(code: String) async -> CodeSubmission {
        guard let session = conduction?.session else { return .noLiveConduction }
        guard SubscriptionToken(pasted: code) == nil else { return .rejectedAsCredential }

        let payload = outbox.load(
            code.trimmingCharacters(in: .whitespacesAndNewlines),
            terminatedBy: Self.carriageReturn
        )
        try? await session.write(payload)
        outbox.wipe()

        return .delivered
    }

    var outboxIsZeroed: Bool {
        outbox.isZeroed
    }

    private func read(
        from session: any PseudoTerminalSession,
        onProgress: @escaping @Sendable (AssistedSetupProgress) -> Void
    ) async -> AssistedSetupOutcome {
        var scanner = SetupTokenScanner()
        defer { scanner.wipe() }

        while true {
            var scanned = SetupTokenScanner.Outcome.pending
            guard let delivered = try? await session.readChunk({ scanned = scanner.consume($0) }) else { break }

            if delivered, conduction?.sawOutput == false {
                conduction?.sawOutput = true
                onProgress(.waitingForApproval)
            }

            switch scanned {
            case .found(let candidate):
                guard let token = SubscriptionToken(pasted: candidate) else {
                    return .unavailable(.endedWithoutCredential)
                }
                return .obtained(token)
            case .exhausted:
                return .unavailable(.endedWithoutCredential)
            case .pending:
                break
            }

            if Task.isCancelled { return .cancelled }
            if let expiry { return .unavailable(expiry) }
            if !delivered { break }
        }

        if Task.isCancelled { return .cancelled }
        if let expiry { return .unavailable(expiry) }

        await session.terminate()
        guard let status = await session.exitStatus(), status != 0 else {
            return .unavailable(.endedWithoutCredential)
        }
        return .unavailable(.refusedByPolicy)
    }

    private func enforceDeadlines(on session: any PseudoTerminalSession) async {
        while !Task.isCancelled {
            guard let verdict = overdue() else {
                try? await clock.sleep(for: timing.pollInterval)
                continue
            }

            expiry = verdict
            await session.terminate()
            return
        }
    }

    private func overdue() -> AssistedSetupUnavailability? {
        guard let conduction else { return nil }

        let elapsed = conduction.startedAt.duration(to: clock.now)
        if !conduction.sawOutput, elapsed >= timing.firstOutput { return .silentBeforeAnySign }
        if elapsed >= timing.total { return .approvalTimedOut }
        return nil
    }
}

extension SetupTokenCredentialAcquirer where Timeline == ContinuousClock {
    public init(
        discover: @escaping @Sendable () async -> ClaudeCodeDiscovery,
        spawner: any PseudoTerminalSpawning,
        home: URL = URL(filePath: NSHomeDirectory()),
        timing: AssistedSetupTiming = .standard
    ) {
        self.init(discover: discover, spawner: spawner, home: home, timing: timing, clock: ContinuousClock())
    }
}
