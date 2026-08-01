import Foundation

@testable import QuotaBarCore

enum TestCycle {
    static func scheduled(
        _ interval: Duration = .seconds(180),
        nature: ScheduledNature = .base,
        id: UInt64 = 1,
        expectedReadingAt: Date? = nil,
        deferralDeadline: Date = .distantFuture
    ) -> CadenceCycle {
        CadenceCycle(
            id: id,
            cadence: ScheduledCadence(interval: interval, nature: nature)!,
            expectedReadingAt: expectedReadingAt ?? TestSnapshot.readAt.adding(interval),
            deferralDeadline: deferralDeadline
        )
    }
}

enum TestSnapshot {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)

    static func utilization(_ percent: String?) -> Utilization? {
        guard let percent, let value = Decimal(string: percent) else { return nil }
        return Utilization(originPercent: value)
    }

    static func make(
        fiveHourPercent: String?,
        sevenDayPercent: String?,
        bindingWindow: BindingWindow?,
        fiveHourResetsAt: Date? = nil,
        sevenDayResetsAt: Date? = nil,
        readSequence: UInt64 = 1,
        readAt: Date = TestSnapshot.readAt,
        source: QuotaSource = .primaryProbe
    ) -> QuotaSnapshot {
        guard let snapshot = build(
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            bindingWindow: bindingWindow,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
            readSequence: readSequence,
            readAt: readAt,
            source: source
        ) else {
            fatalError("leitura de teste inválida: nenhuma janela com percentual")
        }
        return snapshot
    }

    static func build(
        fiveHourPercent: String?,
        sevenDayPercent: String?,
        bindingWindow: BindingWindow?,
        fiveHourResetsAt: Date? = nil,
        sevenDayResetsAt: Date? = nil,
        readSequence: UInt64 = 1,
        readAt: Date = TestSnapshot.readAt,
        source: QuotaSource = .primaryProbe
    ) -> QuotaSnapshot? {
        QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: utilization(fiveHourPercent),
                resetsAt: fiveHourResetsAt,
                status: .allowed
            ),
            sevenDay: WindowReading(
                utilization: utilization(sevenDayPercent),
                resetsAt: sevenDayResetsAt,
                status: .allowed
            ),
            overallStatus: .allowed,
            nextResetAt: nil,
            bindingWindow: bindingWindow,
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: readSequence,
            readAt: readAt,
            source: source
        )
    }
}
