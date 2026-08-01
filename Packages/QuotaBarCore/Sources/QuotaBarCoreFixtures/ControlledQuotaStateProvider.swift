import Foundation
import QuotaBarCore

public actor RefreshLog {
    private var count = 0

    public init() {}

    public func record() {
        count += 1
    }

    public func total() -> Int {
        count
    }
}

public final class ControlledQuotaStateProvider: QuotaStateProviding {
    public let states: AsyncStream<QuotaState>

    private let continuation: AsyncStream<QuotaState>.Continuation
    private let refreshes = RefreshLog()

    public init() {
        let (stream, continuation) = AsyncStream.makeStream(of: QuotaState.self)
        states = stream
        self.continuation = continuation
    }

    public func emit(_ state: QuotaState) {
        continuation.yield(state)
    }

    public func finish() {
        continuation.finish()
    }

    public func refreshNow() async {
        await refreshes.record()
    }

    public func setViewerObserving(_ observing: Bool) async {}

    public func refreshCount() async -> Int {
        await refreshes.total()
    }
}
