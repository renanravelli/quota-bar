import Foundation

public struct StaleLatch: Sendable, Hashable {
    public private(set) var isLatched: Bool
    private var evaluatedReadSequence: UInt64?

    public init() {
        isLatched = false
        evaluatedReadSequence = nil
    }

    public mutating func evaluate(
        readSequence: UInt64,
        readingAt: Date,
        now: Date,
        maxIdleCadenceSinceReading: Duration,
        displayedWindowResetPassed: Bool
    ) -> Bool {
        if readSequence != evaluatedReadSequence {
            evaluatedReadSequence = readSequence
            isLatched = false
        }

        guard !isLatched else { return true }

        let exceededLimit = StalenessPolicy.isStale(
            age: StalenessPolicy.age(ofReadingAt: readingAt, now: now),
            maxIdleCadenceSinceReading: maxIdleCadenceSinceReading
        )
        isLatched = exceededLimit || displayedWindowResetPassed
        return isLatched
    }
}
