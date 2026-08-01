import Foundation

public enum AgeSchedule {
    public static func nextThreshold(for state: QuotaState, now: Date) -> Date? {
        guard let readAt = state.snapshot?.readAt else { return nil }
        return AgeDisplay.nextChange(ofReadingAt: readAt, now: now)
    }
}
