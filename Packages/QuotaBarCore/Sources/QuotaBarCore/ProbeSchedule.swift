import Foundation

public enum ProbeSchedule {
    public static func next(
        scheduled: Date?,
        now: Date,
        newCadence: Duration,
        lastProbeAt: Date
    ) -> Date {
        let byNewCadence = now.adding(newCadence)
        let candidate = scheduled.map { min($0, byNewCadence) } ?? byNewCadence
        return max(candidate, lastProbeAt.adding(Cadence.floor))
    }
}

extension Date {
    func adding(_ duration: Duration) -> Date {
        let components = duration.components
        let seconds = TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1e18
        return addingTimeInterval(seconds)
    }
}
