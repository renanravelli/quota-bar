import Foundation

public enum SeriesRestoration: Sendable, Hashable {
    case intact
    case restartedAfterUnreadableLog
}

public struct SeriesCoverage: Sendable, Hashable {
    public let earliest: Date?
    public let latest: Date?
    public let sampleCount: Int

    public init(of samples: [QuotaSample]) {
        earliest = samples.first?.readAt
        latest = samples.last?.readAt
        sampleCount = samples.count
    }

    public var isEmpty: Bool { sampleCount == 0 }
}

public struct QuotaSampleSeries: Sendable {
    public private(set) var samples: [QuotaSample]
    public let restoration: SeriesRestoration

    private var registeredSequences: Set<UInt64>

    public init(_ samples: [QuotaSample] = [], restoration: SeriesRestoration = .intact) {
        self.samples = []
        self.restoration = restoration
        registeredSequences = []

        for sample in samples { append(sample) }
    }

    public var coverage: SeriesCoverage { SeriesCoverage(of: samples) }

    @discardableResult
    public mutating func append(_ sample: QuotaSample) -> Bool {
        guard registeredSequences.insert(sample.readSequence).inserted else { return false }

        let position = samples.firstIndex { $0.readAt > sample.readAt } ?? samples.endIndex
        samples.insert(sample, at: position)
        return true
    }

    @discardableResult
    public mutating func record(_ state: QuotaState) -> Bool {
        guard case .succeeded = state.lastAttempt, let snapshot = state.snapshot else { return false }
        return append(QuotaSample(snapshot))
    }

    public func samples(of window: QuotaWindow, sinceResetAt: Date) -> [QuotaSample] {
        samples.filter { $0.readAt > sinceResetAt && $0.utilization(of: window) != nil }
    }

    public func gaps(of window: QuotaWindow, over interval: DateInterval) -> [DateInterval] {
        let observed = samples.filter { $0.utilization(of: window) != nil }.map(\.readAt)

        return zip(observed, observed.dropFirst()).compactMap { start, end in
            let from = max(start, interval.start)
            let until = min(end, interval.end)
            guard until > from else { return nil }
            return DateInterval(start: from, end: until)
        }
    }
}
