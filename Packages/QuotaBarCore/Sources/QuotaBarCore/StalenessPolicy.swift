import Foundation

public enum StalenessPolicy {
    public static let floor: Duration = .seconds(600)
    public static let ceiling: Duration = .seconds(2400)

    public static func age(ofReadingAt readingAt: Date, now: Date) -> Duration {
        let elapsed = now.timeIntervalSince(readingAt)
        return elapsed > 0 ? .seconds(elapsed) : .zero
    }

    public static func limit(maxIdleCadenceSinceReading: Duration) -> Duration {
        min(max(maxIdleCadenceSinceReading * 2, floor), ceiling)
    }

    public static func isStale(age: Duration, maxIdleCadenceSinceReading: Duration) -> Bool {
        age > limit(maxIdleCadenceSinceReading: maxIdleCadenceSinceReading)
    }
}
