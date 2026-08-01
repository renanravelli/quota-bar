import Foundation

public enum LifecycleEffect: Sendable, Hashable {
    case suspendProbing
    case resumeAtBaseCadence(nextProbeAt: Date, wokeAt: Date)
}

public actor ProbeLifecycle {
    public static let wakeTolerance: Duration = .seconds(120)

    public nonisolated let effects: AsyncStream<LifecycleEffect>

    private let observer: any SystemPowerEventObserving
    private let activity: any SystemActivityAsserting
    private let time: any DateProviding
    private let publisher: AsyncStream<LifecycleEffect>.Continuation

    private var isSuspended = false
    private var wokeAt: Date?
    private var lastProbeAt: Date?

    public init(
        observing observer: any SystemPowerEventObserving,
        activity: any SystemActivityAsserting,
        time: any DateProviding
    ) {
        self.observer = observer
        self.activity = activity
        self.time = time
        (effects, publisher) = AsyncStream.makeStream(of: LifecycleEffect.self)
    }

    public func run() async {
        for await event in observer.powerEvents {
            publisher.yield(effect(of: event))
        }
        publisher.finish()
    }

    public var allowsProbing: Bool {
        !isSuspended
    }

    public func probing<T: Sendable>(_ probe: @Sendable () async throws -> T) async rethrows -> T? {
        guard allowsProbing else { return nil }

        lastProbeAt = time.now
        let assertion = activity.beginProbeActivity()
        defer { assertion.end() }
        return try await probe()
    }

    public func isWithinWakeTolerance() -> Bool {
        guard let toleranceEnd else { return false }
        return time.now < toleranceEnd
    }

    public func reaction(to reason: FailureReason) -> ProbeReaction {
        NetworkPolicy.reaction(to: reason, withinWakeTolerance: isWithinWakeTolerance())
    }

    public func retryAfterToleratedFailure() -> Date? {
        guard let toleranceEnd, let lastProbeAt, isWithinWakeTolerance() else { return nil }

        let retry = ProbeSchedule.next(
            scheduled: nil,
            now: time.now,
            newCadence: .zero,
            lastProbeAt: lastProbeAt
        )
        return retry < toleranceEnd ? retry : nil
    }

    private var toleranceEnd: Date? {
        wokeAt?.adding(Self.wakeTolerance)
    }

    private func effect(of event: SystemPowerEvent) -> LifecycleEffect {
        let now = time.now
        switch event {
        case .willSleep:
            isSuspended = true
            return .suspendProbing
        case .didWake:
            isSuspended = false
            wokeAt = now
            return .resumeAtBaseCadence(
                nextProbeAt: ProbeSchedule.next(
                    scheduled: nil,
                    now: now,
                    newCadence: .zero,
                    lastProbeAt: lastProbeAt ?? .distantPast
                ),
                wokeAt: now
            )
        }
    }
}
