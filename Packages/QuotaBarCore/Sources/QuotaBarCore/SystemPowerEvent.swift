public enum SystemPowerEvent: Sendable, Hashable {
    case willSleep
    case didWake
}

public protocol SystemPowerEventObserving: Sendable {
    var powerEvents: AsyncStream<SystemPowerEvent> { get }
}
