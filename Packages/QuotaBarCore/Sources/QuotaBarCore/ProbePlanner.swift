import Foundation

public struct ProbePlanner: Sendable {
    public static let baseInterval: Duration = .seconds(180)
    public static let idleCeiling: Duration = .seconds(900)

    public let policy: DeferralPolicy

    public private(set) var cadence: ScheduledCadence
    public private(set) var appointment: ProbeAppointment
    public private(set) var lastProbeAt: Date

    private var idleCadence: MaxIdleCadenceSinceReading
    private var idleInterval: Duration
    private var viewerObserving: Bool
    private var cycleID: UInt64
    private var deferralDeadline: Date

    public var scheduledAt: Date {
        appointment.instant
    }

    public var maxIdleCadenceSinceReading: Duration {
        idleCadence.value
    }

    public var cycle: CadenceCycle {
        CadenceCycle(
            id: cycleID,
            cadence: cadence,
            expectedReadingAt: appointment.instant,
            deferralDeadline: deferralDeadline
        )
    }

    public init(startingAt now: Date, policy: DeferralPolicy = .standard) {
        self.policy = policy
        cadence = .atLeastFloor(Self.baseInterval, .base)
        idleCadence = MaxIdleCadenceSinceReading(atReading: cadence)
        idleInterval = Self.baseInterval
        viewerObserving = false
        lastProbeAt = .distantPast
        cycleID = 1
        appointment = ProbeAppointment(instant: now, anchoredAt: now, intended: cadence.interval)
        deferralDeadline = .distantFuture
        anchor(now, at: now)
    }

    public mutating func setViewerObserving(_ observing: Bool, at now: Date) {
        viewerObserving = observing
        guard observing else { return }
        adopt(.atLeastFloor(Self.baseInterval, .base), at: now)
    }

    public mutating func requestImmediateRead(at now: Date) {
        schedule(after: .zero, keeping: nil, at: now)
    }

    public mutating func recordReading(utilizationChanged: Bool, at now: Date) {
        lastProbeAt = now
        beginCycle()
        cadence = cadenceAfterReading(utilizationChanged: utilizationChanged)
        idleCadence.restart(atReading: cadence)
        schedule(after: cadence.interval, keeping: nil, at: now)
    }

    public mutating func recordThrottling(retryAfter: Duration?, jitter: Double, at now: Date) {
        lastProbeAt = now
        beginCycle()
        widen(retryAfter: retryAfter, jitter: jitter, at: now)
    }

    public mutating func recordFailure(reaction: ProbeReaction, jitter: Double, at now: Date) {
        lastProbeAt = now
        beginCycle()
        switch reaction {
        case .widenCadence:
            widen(retryAfter: nil, jitter: jitter, at: now)
        case .keepCadence, .stopProbing:
            schedule(after: cadence.interval, keeping: nil, at: now)
        }
    }

    public mutating func recordUnreachedAttempt(retryAt instant: Date, decidedAt now: Date) {
        beginCycle()
        anchor(instant, at: now)
    }

    public mutating func resume(nextProbeAt: Date, at now: Date) {
        idleInterval = Self.baseInterval
        beginCycle()
        cadence = .atLeastFloor(Self.baseInterval, .base)
        anchor(nextProbeAt, at: now)
    }

    public mutating func reschedule(at instant: Date, decidedAt now: Date) {
        anchor(instant, at: now)
    }

    private mutating func adopt(_ newCadence: ScheduledCadence, at now: Date) {
        cadence = newCadence
        idleCadence.observe(newCadence)
        schedule(after: newCadence.interval, keeping: scheduledAt, at: now)
    }

    private mutating func widen(retryAfter: Duration?, jitter: Double, at now: Date) {
        let widened = BackoffPolicy.widened(from: cadence.interval, retryAfter: retryAfter, jitter: jitter)
        cadence = .atLeastFloor(widened, .widenedByFailure)
        schedule(after: widened, keeping: nil, at: now)
    }

    private mutating func cadenceAfterReading(utilizationChanged: Bool) -> ScheduledCadence {
        guard !viewerObserving, !utilizationChanged else {
            idleInterval = Self.baseInterval
            return .atLeastFloor(Self.baseInterval, .base)
        }

        idleInterval = min(idleInterval * 2, Self.idleCeiling)
        return .atLeastFloor(idleInterval, .idle)
    }

    private mutating func schedule(after interval: Duration, keeping scheduled: Date?, at now: Date) {
        anchor(
            ProbeSchedule.next(
                scheduled: scheduled,
                now: now,
                newCadence: interval,
                lastProbeAt: lastProbeAt
            ),
            at: now
        )
    }

    private mutating func beginCycle() {
        cycleID += 1
        deferralDeadline = .distantFuture
    }

    private mutating func anchor(_ instant: Date, at now: Date) {
        appointment = ProbeAppointment(instant: instant, anchoredAt: now, intended: cadence.interval)
        deferralDeadline = min(deferralDeadline, policy.deadline(for: appointment))
    }
}

private extension ScheduledCadence {
    static func atLeastFloor(_ interval: Duration, _ nature: ScheduledNature) -> ScheduledCadence {
        ScheduledCadence(interval: max(interval, floor), nature: nature)!
    }
}
