import Foundation

public enum StalenessSchedule {
    public static func nextThreshold(for state: QuotaState, now: Date) -> Date? {
        guard let snapshot = state.snapshot,
              let selection = WindowSelector.select(from: snapshot)
        else { return nil }

        let limit = StalenessPolicy.limit(maxIdleCadenceSinceReading: state.maxIdleCadenceSinceReading)
        let stalenessDeadline = snapshot.readAt.addingTimeInterval(seconds(of: limit))
        let windowReset = snapshot.reading(for: selection.window).resetsAt

        return [stalenessDeadline, windowReset]
            .compactMap { $0 }
            .filter { $0 > now }
            .min()
    }

    private static func seconds(of duration: Duration) -> TimeInterval {
        TimeInterval(duration.components.seconds)
    }
}
