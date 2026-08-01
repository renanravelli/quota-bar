import Foundation

public struct ProjectionLatch: Sendable {
    public private(set) var projection: Projection
    public private(set) var computedAt: Date?

    private var evaluated: Trigger?

    public init() {
        projection = .unavailable(.seriesBeginsAtFirstReading)
        computedAt = nil
        evaluated = nil
    }

    public mutating func update(
        with series: QuotaSampleSeries,
        window: QuotaWindow,
        sinceResetAt: Date,
        maxIdleCadence: Duration,
        now: Date
    ) {
        let observed = Trigger(series: series, window: window, sinceResetAt: sinceResetAt)
        guard observed != evaluated else { return }

        evaluated = observed
        projection = ProjectionPolicy.project(
            series,
            window: window,
            sinceResetAt: sinceResetAt,
            maxIdleCadence: maxIdleCadence,
            now: now
        )
        computedAt = now
    }
}

private struct Trigger: Sendable, Hashable {
    let latestReadSequence: UInt64?
    let sampleCount: Int
    let sinceResetAt: Date
    let resetsAt: Date?

    init(series: QuotaSampleSeries, window: QuotaWindow, sinceResetAt: Date) {
        latestReadSequence = series.samples.last?.readSequence
        sampleCount = series.samples.count
        self.sinceResetAt = sinceResetAt
        resetsAt = series.samples.last?.resetsAt(of: window)
    }
}
