import Foundation
import QuotaBarCore

public actor ProbingQuotaStateProvider: QuotaStateProviding {
    public nonisolated let states: AsyncStream<QuotaState>

    private let probe: QuotaProbe
    private let credentials: any CredentialStoring
    private let lifecycle: ProbeLifecycle
    private let store: any QuotaSnapshotStoring
    private let time: any DateProviding
    private let waiter: any DeadlineWaiting
    private let jitter: @Sendable () -> Double
    private let publisher: AsyncStream<QuotaState>.Continuation

    private var claudeCode: ClaudeCodeVersionResolver
    private var discovery: ClaudeCodeDiscovery?
    private var plan: ProbePlanner
    private var snapshot: QuotaSnapshot?
    private var lastAttempt: AttemptOutcome
    private var credentialPresent: Bool
    private var halted: Bool
    private var pendingWait: Task<Void, Never>?

    public init(
        probe: QuotaProbe,
        credentials: any CredentialStoring,
        environment: any ClaudeCodeEnvironment,
        lifecycle: ProbeLifecycle,
        store: any QuotaSnapshotStoring,
        time: any DateProviding = SystemDate(),
        waiter: (any DeadlineWaiting)? = nil,
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        self.probe = probe
        self.credentials = credentials
        self.lifecycle = lifecycle
        self.store = store
        self.time = time
        self.waiter = waiter ?? SystemDeadlineWaiter(time: time)
        self.jitter = jitter
        claudeCode = ClaudeCodeVersionResolver(environment: environment)
        plan = ProbePlanner(startingAt: time.now)
        lastAttempt = .inProgress
        credentialPresent = false
        halted = false
        (states, publisher) = AsyncStream.makeStream(of: QuotaState.self)
    }

    public func run() async {
        await reviewCredentialPresence()
        await restoreLastReading()
        publish()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.followLifecycle() }
            group.addTask { await self.probePeriodically() }
        }

        publisher.finish()
    }

    public func refreshNow() async {
        halted = false
        plan.requestImmediateRead(at: time.now)
        interrupt()
    }

    public func setViewerObserving(_ observing: Bool) async {
        plan.setViewerObserving(observing, at: time.now)
        publish()
        interrupt()
    }

    private func probePeriodically() async {
        while !Task.isCancelled {
            await awaitScheduledInstant()
            guard !Task.isCancelled else { return }
            guard await probingAllowed, plan.scheduledAt <= time.now else { continue }
            await probeOnce()
        }
    }

    private func awaitScheduledInstant() async {
        let deadline = await probingAllowed ? plan.scheduledAt : .distantFuture
        guard deadline > time.now else { return }

        let waiting = Task { [waiter] in await waiter.wait(until: deadline) }
        pendingWait = waiting
        await withTaskCancellationHandler {
            await waiting.value
        } onCancel: {
            waiting.cancel()
        }
        pendingWait = nil
    }

    private func interrupt() {
        pendingWait?.cancel()
    }

    private var probingAllowed: Bool {
        get async {
            guard !halted else { return false }
            return await lifecycle.allowsProbing
        }
    }

    private var probingConfigured: Bool {
        credentialPresent && discovery?.allowsProbe == true
    }

    private var probingScheduled: Bool {
        probingConfigured && !halted
    }

    private func probeOnce() async {
        let now = time.now
        await reviewCredentialPresence()
        let found = claudeCode.resolve()
        discovery = found

        guard let version = found.version else {
            lastAttempt = .failed(.claudeCodeNotFound)
            plan.recordUnreachedAttempt(retryAt: now.adding(ProbePlanner.baseInterval), decidedAt: now)
            publish()
            return
        }

        guard let outcome = await lifecycle.probing({ [probe] in
            await probe.read(claudeCodeVersion: version, at: now)
        }) else {
            plan.reschedule(at: now.adding(plan.cadence.interval), decidedAt: now)
            publish()
            return
        }

        switch outcome {
        case .credentialUnavailable(let failure):
            apply(failure, at: now)
        case .probed(let result):
            await apply(result, at: now)
        }

        publish()
    }

    private func restoreLastReading() async {
        guard let restored = await store.restore() else { return }
        snapshot = restored
        await probe.continueReadSequence(after: restored.readSequence)
    }

    private func reviewCredentialPresence() async {
        guard case .success(let configured) = await credentials.isConfigured() else { return }
        credentialPresent = configured
    }

    private func apply(_ failure: KeychainFailure, at now: Date) {
        guard failure != .itemNotFound else {
            credentialPresent = false
            lastAttempt = .inProgress
            plan.reschedule(at: now.adding(ProbePlanner.baseInterval), decidedAt: now)
            return
        }

        credentialPresent = true
        lastAttempt = .failed(.credentialUnreadable)
        halted = true
        plan.recordFailure(reaction: .stopProbing, jitter: jitter(), at: now)
    }

    private func apply(_ result: ProbeResult, at now: Date) async {
        credentialPresent = true

        switch result {
        case .reading(let reading):
            let changed = Self.utilizationChanged(from: snapshot, to: reading)
            snapshot = reading
            lastAttempt = .succeeded(at: now)
            plan.recordReading(utilizationChanged: changed, at: now)
            await store.persist(reading)

        case .throttled(let retryAfter):
            lastAttempt = .failed(.communicationFailure)
            plan.recordThrottling(retryAfter: retryAfter, jitter: jitter(), at: now)

        case .failed(let reason):
            lastAttempt = .failed(reason)
            let reaction = await lifecycle.reaction(to: reason)
            halted = reaction == .stopProbing
            plan.recordFailure(reaction: reaction, jitter: jitter(), at: now)

            if reaction == .keepCadence, let retry = await lifecycle.retryAfterToleratedFailure() {
                plan.reschedule(at: retry, decidedAt: now)
            }
        }
    }

    private func followLifecycle() async {
        for await effect in lifecycle.effects {
            if case .resumeAtBaseCadence(let nextProbeAt, let wokeAt) = effect {
                plan.resume(nextProbeAt: nextProbeAt, at: wokeAt)
                publish()
            }
            interrupt()
        }
    }

    private func publish() {
        publisher.yield(
            QuotaState(
                credentialPresent: credentialPresent,
                claudeCodeMissing: discovery == .notFound,
                snapshot: snapshot,
                lastAttempt: lastAttempt,
                cycle: probingScheduled ? plan.cycle : nil,
                maxIdleCadenceSinceReading: plan.maxIdleCadenceSinceReading,
                source: probingConfigured ? .primaryProbe : nil,
                unavailableFields: snapshot?.unavailableFields ?? []
            )
        )
    }

    private static func utilizationChanged(from previous: QuotaSnapshot?, to current: QuotaSnapshot) -> Bool {
        guard let previous else { return true }
        return previous.fiveHour.utilization != current.fiveHour.utilization
            || previous.sevenDay.utilization != current.sevenDay.utilization
    }
}

private extension Date {
    func adding(_ duration: Duration) -> Date {
        addingTimeInterval(TimeInterval(duration.components.seconds))
    }
}
