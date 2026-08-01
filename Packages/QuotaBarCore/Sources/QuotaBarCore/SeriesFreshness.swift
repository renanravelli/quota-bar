import Foundation

public enum SeriesFreshness: Sendable, Hashable {
    case neverObserved
    case fresh(age: Duration)
    case stale(age: Duration)

    public static func of(
        lastObservedAt: Date?,
        at instant: Date,
        maxIdleCadenceSinceReading: Duration
    ) -> SeriesFreshness {
        guard let lastObservedAt else { return .neverObserved }

        let age = StalenessPolicy.age(ofReadingAt: lastObservedAt, now: instant)
        let isStale = StalenessPolicy.isStale(
            age: age,
            maxIdleCadenceSinceReading: maxIdleCadenceSinceReading
        )
        return isStale ? .stale(age: age) : .fresh(age: age)
    }
}
