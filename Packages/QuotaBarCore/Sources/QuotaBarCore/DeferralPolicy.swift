import Foundation

public struct DeferralPolicy: Sendable, Hashable {
    public static let standard = DeferralPolicy(tolerance: 0.5)

    public let tolerance: Double

    public init(tolerance: Double) {
        self.tolerance = tolerance
    }

    public func deadline(for appointment: ProbeAppointment) -> Date {
        appointment.anchoredAt.adding(appointment.intended * (1 + tolerance))
    }

    public func isDeferred(_ appointment: ProbeAppointment, at now: Date) -> Bool {
        now > deadline(for: appointment)
    }
}
