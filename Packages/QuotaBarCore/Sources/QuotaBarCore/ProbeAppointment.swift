import Foundation

public struct ProbeAppointment: Sendable, Hashable {
    public let instant: Date
    public let anchoredAt: Date
    public let intended: Duration

    public init(instant: Date, anchoredAt: Date, intended: Duration) {
        self.instant = instant
        self.anchoredAt = anchoredAt
        self.intended = intended
    }
}
