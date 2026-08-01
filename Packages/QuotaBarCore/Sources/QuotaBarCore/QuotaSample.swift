import Foundation

public struct QuotaSample: Sendable, Hashable {
    public let readAt: Date
    public let readSequence: UInt64
    public let fiveHour: Utilization?
    public let sevenDay: Utilization?
    public let fiveHourResetsAt: Date?
    public let sevenDayResetsAt: Date?
    public let source: QuotaSource

    public init(
        readAt: Date,
        readSequence: UInt64,
        fiveHour: Utilization?,
        sevenDay: Utilization?,
        fiveHourResetsAt: Date?,
        sevenDayResetsAt: Date?,
        source: QuotaSource
    ) {
        self.readAt = readAt
        self.readSequence = readSequence
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayResetsAt = sevenDayResetsAt
        self.source = source
    }

    public init(_ snapshot: QuotaSnapshot) {
        self.init(
            readAt: snapshot.readAt,
            readSequence: snapshot.readSequence,
            fiveHour: snapshot.fiveHour.utilization,
            sevenDay: snapshot.sevenDay.utilization,
            fiveHourResetsAt: snapshot.fiveHour.resetsAt,
            sevenDayResetsAt: snapshot.sevenDay.resetsAt,
            source: snapshot.source
        )
    }

    public func utilization(of window: QuotaWindow) -> Utilization? {
        switch window {
        case .fiveHour: fiveHour
        case .sevenDay: sevenDay
        }
    }

    public func resetsAt(of window: QuotaWindow) -> Date? {
        switch window {
        case .fiveHour: fiveHourResetsAt
        case .sevenDay: sevenDayResetsAt
        }
    }
}
