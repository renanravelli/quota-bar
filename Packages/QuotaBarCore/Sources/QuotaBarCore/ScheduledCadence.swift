public enum ScheduledNature: Sendable, Hashable, CaseIterable {
    case base
    case idle
    case widenedByFailure

    public var raisesMaxIdleCadence: Bool {
        switch self {
        case .base, .idle: true
        case .widenedByFailure: false
        }
    }

    public var observed: Cadence.Nature {
        switch self {
        case .base: .base
        case .idle: .idle
        case .widenedByFailure: .widenedByFailure
        }
    }
}

public struct ScheduledCadence: Sendable, Hashable {
    public static let floor: Duration = Cadence.floor

    public let interval: Duration
    public let nature: ScheduledNature

    public init?(interval: Duration, nature: ScheduledNature) {
        guard interval >= Self.floor else { return nil }
        self.interval = interval
        self.nature = nature
    }

    public var observed: Cadence {
        Cadence(interval: interval, nature: nature.observed)!
    }
}
