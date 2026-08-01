import Foundation

public enum BucketSize: Sendable, Hashable {
    case hour
    case day
    case week
}

public struct BucketKey: Sendable, Hashable, Comparable {
    public let start: Date
    public let size: BucketSize

    public init(start: Date, size: BucketSize) {
        self.start = start
        self.size = size
    }

    public static func < (lhs: BucketKey, rhs: BucketKey) -> Bool {
        lhs.start < rhs.start
    }
}

public enum BucketValue: Sendable, Hashable {
    case measured(TokenCounts)
    case noCoverage
}

public struct Coverage: Sendable, Hashable {
    public let earliest: Date?
    public let latest: Date?
    public let observedBuckets: Int
    public let isIntact: Bool

    public init(earliest: Date?, latest: Date?, observedBuckets: Int, isIntact: Bool) {
        self.earliest = earliest
        self.latest = latest
        self.observedBuckets = observedBuckets
        self.isIntact = isIntact
    }

    public var span: Duration? {
        guard let earliest, let latest else { return nil }
        return .seconds(latest.timeIntervalSince(earliest))
    }
}

public struct CoverageReport: Sendable, Hashable {
    public let events: Int
    public let filesRead: Int
    public let filesUnread: Int
    public let recordsIgnored: Int
    public let duplicatesDiscarded: Int
    public let earliestEventAt: Date?
    public let latestEventAt: Date?

    public init(
        events: Int = 0,
        filesRead: Int = 0,
        filesUnread: Int = 0,
        recordsIgnored: Int = 0,
        duplicatesDiscarded: Int = 0,
        earliestEventAt: Date? = nil,
        latestEventAt: Date? = nil
    ) {
        self.events = events
        self.filesRead = filesRead
        self.filesUnread = filesUnread
        self.recordsIgnored = recordsIgnored
        self.duplicatesDiscarded = duplicatesDiscarded
        self.earliestEventAt = earliestEventAt
        self.latestEventAt = latestEventAt
    }
}

public struct UsageSeries: Sendable, Hashable {
    public struct Bucket: Sendable, Hashable {
        public let key: BucketKey
        public let value: BucketValue
        public let byModel: [ModelIdentity: TokenCounts]

        public init(key: BucketKey, value: BucketValue, byModel: [ModelIdentity: TokenCounts]) {
            self.key = key
            self.value = value
            self.byModel = byModel
        }
    }

    public let window: SeriesWindow
    public let size: BucketSize
    public let buckets: [Bucket]

    public init(window: SeriesWindow, size: BucketSize, buckets: [Bucket]) {
        self.window = window
        self.size = size
        self.buckets = buckets
    }
}

public struct UsageAggregate: Sendable, Hashable {
    struct Address: Sendable, Hashable {
        let model: ModelIdentity
        let hourStart: Date
    }

    private let hourly: [Address: TokenCounts]
    public let coverage: Coverage
    public let report: CoverageReport

    init(hourly: [Address: TokenCounts], coverage: Coverage, report: CoverageReport) {
        self.hourly = hourly
        self.coverage = coverage
        self.report = report
    }

    public static let empty = UsageAggregate(
        hourly: [:],
        coverage: Coverage(earliest: nil, latest: nil, observedBuckets: 0, isIntact: true),
        report: CoverageReport()
    )

    public var models: [ModelIdentity] {
        Set(hourly.keys.map(\.model)).sorted()
    }

    public func totals(of model: ModelIdentity) -> TokenCounts {
        hourly.reduce(.zero) { $0 + ($1.key.model == model ? $1.value : .zero) }
    }

    public var totalsByModel: [ModelIdentity: TokenCounts] {
        hourly.reduce(into: [:]) { totals, entry in
            totals[entry.key.model, default: .zero] += entry.value
        }
    }

    public func value(at key: BucketKey, model: ModelIdentity?, calendar: Calendar) -> BucketValue {
        guard let earliest = coverage.earliest, let latest = coverage.latest else { return .noCoverage }

        let bounds = BucketCalendar.range(of: key, calendar: calendar)
        guard bounds.upperBound > BucketCalendar.start(of: earliest, size: key.size, calendar: calendar),
              bounds.lowerBound <= latest
        else { return .noCoverage }

        let counts = accumulate(in: bounds, model: model, calendar: calendar)
        if counts == .zero, !hasObservation(in: bounds, model: model, calendar: calendar) {
            return coverage.isIntact ? .measured(.zero) : .noCoverage
        }
        return .measured(counts)
    }

    public func series(over window: SeriesWindow, now: Date, calendar: Calendar) -> UsageSeries {
        let size = DisplayGranularity.bucketSize(for: window, coverage: coverage)
        guard let earliest = coverage.earliest, let latest = coverage.latest else {
            return UsageSeries(window: window, size: size, buckets: [])
        }

        let selected = window.interval(now: now, coverage: coverage, calendar: calendar)
        let lowerBound = max(selected.start, earliest)
        let upperBound = min(selected.end, latest)
        guard lowerBound <= upperBound else {
            return UsageSeries(window: window, size: size, buckets: [])
        }

        let starts = BucketCalendar.starts(
            from: lowerBound,
            through: upperBound,
            size: size,
            calendar: calendar
        )

        let buckets = starts.map { start -> UsageSeries.Bucket in
            let key = BucketKey(start: start, size: size)
            let bounds = BucketCalendar.range(of: key, calendar: calendar)
            let byModel = accumulateByModel(in: bounds, calendar: calendar)
            let counts = byModel.values.reduce(.zero, +)
            let value: BucketValue = byModel.isEmpty
                ? (coverage.isIntact ? .measured(.zero) : .noCoverage)
                : .measured(counts)
            return UsageSeries.Bucket(key: key, value: value, byModel: byModel)
        }

        return UsageSeries(window: window, size: size, buckets: buckets)
    }

    private func accumulate(in bounds: Range<Date>, model: ModelIdentity?, calendar: Calendar) -> TokenCounts {
        hourly.reduce(.zero) { running, entry in
            guard bounds.contains(entry.key.hourStart) else { return running }
            guard model == nil || entry.key.model == model else { return running }
            return running + entry.value
        }
    }

    private func hasObservation(in bounds: Range<Date>, model: ModelIdentity?, calendar: Calendar) -> Bool {
        hourly.contains { entry in
            bounds.contains(entry.key.hourStart) && (model == nil || entry.key.model == model)
        }
    }

    private func accumulateByModel(in bounds: Range<Date>, calendar: Calendar) -> [ModelIdentity: TokenCounts] {
        hourly.reduce(into: [:]) { totals, entry in
            guard bounds.contains(entry.key.hourStart) else { return }
            totals[entry.key.model, default: .zero] += entry.value
        }
    }
}

enum BucketCalendar {
    static func start(of instant: Date, size: BucketSize, calendar: Calendar) -> Date {
        switch size {
        case .hour:
            let parts = calendar.dateComponents([.year, .month, .day, .hour], from: instant)
            return calendar.date(from: parts) ?? instant
        case .day:
            return calendar.startOfDay(for: instant)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: instant)?.start
                ?? calendar.startOfDay(for: instant)
        }
    }

    static func range(of key: BucketKey, calendar: Calendar) -> Range<Date> {
        let component: Calendar.Component = switch key.size {
        case .hour: .hour
        case .day: .day
        case .week: .weekOfYear
        }
        let end = calendar.date(byAdding: component, value: 1, to: key.start) ?? key.start
        return key.start..<end
    }

    static func starts(from: Date, through: Date, size: BucketSize, calendar: Calendar) -> [Date] {
        let first = start(of: from, size: size, calendar: calendar)
        var result = [first]
        var seen: Set<Date> = [first]

        calendar.enumerateDates(
            startingAfter: first,
            matching: matching(size, calendar: calendar),
            matchingPolicy: .strict,
            direction: .forward
        ) { candidate, _, stop in
            guard let candidate, candidate <= through else {
                stop = true
                return
            }
            let canonical = start(of: candidate, size: size, calendar: calendar)
            if seen.insert(canonical).inserted { result.append(canonical) }
        }

        return result
    }

    private static func matching(_ size: BucketSize, calendar: Calendar) -> DateComponents {
        switch size {
        case .hour: DateComponents(minute: 0, second: 0)
        case .day: DateComponents(hour: 0, minute: 0, second: 0)
        case .week: DateComponents(hour: 0, minute: 0, second: 0, weekday: calendar.firstWeekday)
        }
    }
}
