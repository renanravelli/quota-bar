import Foundation

public struct DeferralLatch: Sendable, Hashable {
    private var evaluatedCycle: UInt64?
    private var isLatched: Bool

    public init() {
        evaluatedCycle = nil
        isLatched = false
    }

    public mutating func evaluate(cycle: CadenceCycle, now: Date) -> Bool {
        if cycle.id != evaluatedCycle {
            evaluatedCycle = cycle.id
            isLatched = false
        }

        guard !isLatched else { return true }

        isLatched = now > cycle.deferralDeadline
        return isLatched
    }
}

public extension QuotaState {
    func cadence(at now: Date, latch: inout DeferralLatch) -> Cadence? {
        guard let cycle else { return nil }

        return latch.evaluate(cycle: cycle, now: now)
            ? Cadence(interval: cycle.cadence.interval, nature: .deferredBySystem)!
            : cycle.cadence.observed
    }
}
