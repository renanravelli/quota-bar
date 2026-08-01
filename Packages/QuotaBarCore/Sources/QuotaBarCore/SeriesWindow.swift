import Foundation

public enum SeriesWindow: Sendable, Hashable, CaseIterable {
    case today
    case week
    case month
    case everything

    public func interval(now: Date, coverage: Coverage, calendar: Calendar) -> DateInterval {
        switch self {
        case .today:
            DateInterval(start: calendar.startOfDay(for: now), end: now)
        case .week:
            DateInterval(start: calendar.date(byAdding: .day, value: -7, to: now) ?? now, end: now)
        case .month:
            DateInterval(start: calendar.date(byAdding: .day, value: -30, to: now) ?? now, end: now)
        case .everything:
            DateInterval(start: min(coverage.earliest ?? now, now), end: now)
        }
    }
}

public enum DisplayGranularity {
    public static let weekThreshold: Duration = .seconds(180 * 24 * 3_600)

    public static func bucketSize(for window: SeriesWindow, coverage: Coverage) -> BucketSize {
        switch window {
        case .today, .week: .hour
        case .month: .day
        case .everything: (coverage.span ?? .zero) > weekThreshold ? .week : .day
        }
    }
}
