import Foundation
import QuotaBarCore

final class RenderLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var instants: [Date] = []

    var recorded: [Date] {
        lock.withLock { instants }
    }

    var record: @MainActor () -> Void {
        { [self] in lock.withLock { instants.append(Date()) } }
    }
}

final class SettableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date

    init(_ instant: Date) {
        self.instant = instant
    }

    var now: Date {
        lock.withLock { instant }
    }

    func set(_ updated: Date) {
        lock.withLock { instant = updated }
    }

    var read: @Sendable () -> Date {
        { [self] in now }
    }
}

final class AnchoredClock: Sendable {
    private let origin: Date
    private let anchoredAt = Date()

    init(origin: Date) {
        self.origin = origin
    }

    var read: @Sendable () -> Date {
        { [origin, anchoredAt] in origin.addingTimeInterval(Date().timeIntervalSince(anchoredAt)) }
    }
}

enum TestCycle {
    static func scheduled(
        _ interval: Duration = .seconds(180),
        nature: ScheduledNature = .base,
        id: UInt64 = 1,
        deferralDeadline: Date = .distantFuture
    ) -> CadenceCycle {
        CadenceCycle(
            id: id,
            cadence: ScheduledCadence(interval: interval, nature: nature)!,
            deferralDeadline: deferralDeadline
        )
    }
}

actor ViewerLedger {
    private(set) var signals: [Bool] = []
    private(set) var refreshes = 0

    func record(observing: Bool) {
        signals.append(observing)
    }

    func recordRefresh() {
        refreshes += 1
    }
}

final class RecordingQuotaStateProvider: QuotaStateProviding {
    let states: AsyncStream<QuotaState>

    private let continuation: AsyncStream<QuotaState>.Continuation
    private let ledger = ViewerLedger()

    init() {
        (states, continuation) = AsyncStream.makeStream(of: QuotaState.self)
    }

    var viewerSignals: [Bool] {
        get async { await ledger.signals }
    }

    var refreshCount: Int {
        get async { await ledger.refreshes }
    }

    func emit(_ state: QuotaState) {
        continuation.yield(state)
    }

    func refreshNow() async {
        await ledger.recordRefresh()
    }

    func setViewerObserving(_ observing: Bool) async {
        await ledger.record(observing: observing)
    }
}

@MainActor
enum Wait {
    static func until(_ reached: () async -> Bool) async {
        for _ in 0..<10_000 {
            if await reached() { return }
            await Task.yield()
        }
    }
}
