public struct Cadence: Sendable, Hashable {
    public enum Nature: Sendable, Hashable {
        case base
        case idle
        case widenedByFailure
        case deferredBySystem
    }

    public static let floor: Duration = .seconds(60)

    public let interval: Duration
    public let nature: Nature

    public init?(interval: Duration, nature: Nature) {
        guard interval >= Self.floor else { return nil }
        self.interval = interval
        self.nature = nature
    }
}
