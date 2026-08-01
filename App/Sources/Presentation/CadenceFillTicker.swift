import Foundation
import QuotaBarCore

enum CadenceFillPolicy {
    static let stepsPerCadence = 120
    static let fastest: Duration = .seconds(1)
    static let slowest: Duration = .seconds(5)

    static func refreshInterval(for cadence: Duration) -> Duration {
        min(max(cadence / stepsPerCadence, fastest), slowest)
    }
}

@MainActor
final class CadenceFillTicker {
    private(set) var isRunning = false
    private(set) var tickCount = 0
    private(set) var currentInterval: Duration?

    private var task: Task<Void, Never>?
    private let requestRender: @MainActor () -> Void

    init(requestRender: @escaping @MainActor () -> Void = {}) {
        self.requestRender = requestRender
    }

    deinit {
        task?.cancel()
    }

    func start(cadence: ScheduledCadence?) {
        stop()

        guard let cadence else { return }

        let interval = CadenceFillPolicy.refreshInterval(for: cadence.interval)
        isRunning = true
        currentInterval = interval

        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.advance()
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
}
