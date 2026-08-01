import Foundation
import os

@testable import QuotaBarCore

final class ControlledPowerEvents: SystemPowerEventObserving, Sendable {
    let powerEvents: AsyncStream<SystemPowerEvent>
    private let continuation: AsyncStream<SystemPowerEvent>.Continuation

    init() {
        (powerEvents, continuation) = AsyncStream.makeStream(of: SystemPowerEvent.self)
    }

    func send(_ event: SystemPowerEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }
}

final class SettableClock: DateProviding, Sendable {
    private let instant: OSAllocatedUnfairLock<Date>

    init(at instant: Date) {
        self.instant = OSAllocatedUnfairLock(initialState: instant)
    }

    var now: Date {
        instant.withLock { $0 }
    }

    func advance(by seconds: TimeInterval) {
        instant.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

final class ActivitySpy: SystemActivityAsserting, Sendable {
    struct Ledger: Sendable {
        var begun = 0
        var ended = 0
    }

    private let ledger = OSAllocatedUnfairLock(initialState: Ledger())

    var record: Ledger {
        ledger.withLock { $0 }
    }

    var held: Int {
        let record = self.record
        return record.begun - record.ended
    }

    func beginProbeActivity() -> SystemActivityAssertion {
        ledger.withLock { $0.begun += 1 }
        return SystemActivityAssertion { [ledger] in
            ledger.withLock { $0.ended += 1 }
        }
    }
}

final class LifecycleHarness {
    let clock: SettableClock
    let events = ControlledPowerEvents()
    let activity = ActivitySpy()
    let lifecycle: ProbeLifecycle

    private var effects: AsyncStream<LifecycleEffect>.AsyncIterator
    private let running: Task<Void, Never>

    init(at instant: Date) {
        let clock = SettableClock(at: instant)
        let lifecycle = ProbeLifecycle(observing: events, activity: activity, time: clock)
        self.clock = clock
        self.lifecycle = lifecycle
        effects = lifecycle.effects.makeAsyncIterator()
        running = Task { await lifecycle.run() }
    }

    deinit {
        events.finish()
        running.cancel()
    }

    func deliver(_ event: SystemPowerEvent) async -> LifecycleEffect? {
        events.send(event)
        return await effects.next()
    }
}
