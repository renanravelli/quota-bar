import Foundation

public struct CadenceCycle: Sendable, Hashable {
    public let id: UInt64
    public let cadence: ScheduledCadence
    public let deferralDeadline: Date

    public init(id: UInt64, cadence: ScheduledCadence, deferralDeadline: Date) {
        self.id = id
        self.cadence = cadence
        self.deferralDeadline = deferralDeadline
    }
}
