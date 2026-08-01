import Foundation
import QuotaBarCore

public final class StableQuotaStateProvider: QuotaStateProviding {
    public let states: AsyncStream<QuotaState>

    public init(
        fiveHourPercent: Decimal = 62,
        sevenDayPercent: Decimal = 41,
        resetsIn: Duration = .seconds(1_800),
        readAt: Date = Date()
    ) {
        let (stream, continuation) = AsyncStream.makeStream(of: QuotaState.self)
        states = stream

        continuation.yield(
            Self.state(
                fiveHourPercent: fiveHourPercent,
                sevenDayPercent: sevenDayPercent,
                resetsIn: resetsIn,
                readAt: readAt
            )
        )
    }

    public func refreshNow() async {}

    public func setViewerObserving(_ observing: Bool) async {}

    private static func state(
        fiveHourPercent: Decimal,
        sevenDayPercent: Decimal,
        resetsIn: Duration,
        readAt: Date
    ) -> QuotaState {
        let resetsAt = readAt.addingTimeInterval(TimeInterval(resetsIn.components.seconds))
        let snapshot = QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: Utilization(originPercent: fiveHourPercent),
                resetsAt: resetsAt,
                status: .allowed
            ),
            sevenDay: WindowReading(
                utilization: Utilization(originPercent: sevenDayPercent),
                resetsAt: readAt.addingTimeInterval(86_400),
                status: .allowed
            ),
            overallStatus: .allowed,
            nextResetAt: resetsAt,
            bindingWindow: .window(.fiveHour),
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: 1,
            readAt: readAt,
            source: .primaryProbe
        )

        return QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .succeeded(at: readAt),
            cycle: CadenceCycle(
                id: 1,
                cadence: ScheduledCadence(interval: .seconds(180), nature: .base)!,
                expectedReadingAt: readAt.addingTimeInterval(180),
                deferralDeadline: .distantFuture
            ),
            maxIdleCadenceSinceReading: .seconds(180),
            source: .primaryProbe,
            unavailableFields: snapshot?.unavailableFields ?? []
        )
    }
}
