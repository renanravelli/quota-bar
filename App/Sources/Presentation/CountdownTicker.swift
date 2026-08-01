import Foundation
import QuotaBarCore

@MainActor
final class CountdownTicker {
    private(set) var isRunning = false
    private(set) var tickCount = 0
    private(set) var currentInterval: Duration?

    private var task: Task<Void, Never>?
    private let clock: @Sendable () -> Date
    private let requestRender: @MainActor () -> Void

    init(
        clock: @escaping @Sendable () -> Date = Date.init,
        requestRender: @escaping @MainActor () -> Void = {}
    ) {
        self.clock = clock
        self.requestRender = requestRender
    }

    deinit {
        task?.cancel()
    }

    func start(nextDeadline: Date?) {
        stop()

        guard let nextDeadline else { return }

        isRunning = true

        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let interval = self.interval(until: nextDeadline) else { return }
                self.currentInterval = interval

                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }

                self.advance()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        currentInterval = nil
    }

    private func advance() {
        tickCount += 1
        requestRender()
    }

    private func interval(until deadline: Date) -> Duration? {
        let remaining = Duration.seconds(max(0, deadline.timeIntervalSince(clock())))
        return CountdownPolicy.refreshInterval(for: CountdownPolicy.format(remaining: remaining))
    }
}
