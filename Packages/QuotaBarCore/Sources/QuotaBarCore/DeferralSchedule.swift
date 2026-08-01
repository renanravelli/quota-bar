import Foundation

public enum DeferralSchedule {
    public static func nextThreshold(for state: QuotaState, now: Date) -> Date? {
        guard let deadline = state.cycle?.deferralDeadline, deadline > now else { return nil }
        return deadline
    }
}
