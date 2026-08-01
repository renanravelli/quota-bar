public struct MaxIdleCadenceSinceReading: Sendable, Hashable {
    public private(set) var value: Duration

    public init(atReading cadence: ScheduledCadence) {
        value = .zero
        observe(cadence)
    }

    public mutating func observe(_ cadence: ScheduledCadence) {
        guard cadence.nature.raisesMaxIdleCadence else { return }
        value = max(value, cadence.interval)
    }

    public mutating func restart(atReading cadence: ScheduledCadence) {
        self = MaxIdleCadenceSinceReading(atReading: cadence)
    }
}
