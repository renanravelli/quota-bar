import Foundation

public struct CadenceCycle: Sendable, Hashable {
    public let id: UInt64
    public let cadence: ScheduledCadence
    public let expectedReadingAt: Date
    public let deferralDeadline: Date

    public init(id: UInt64, cadence: ScheduledCadence, expectedReadingAt: Date, deferralDeadline: Date) {
        self.id = id
        self.cadence = cadence
        self.expectedReadingAt = expectedReadingAt
        self.deferralDeadline = deferralDeadline
    }
}
