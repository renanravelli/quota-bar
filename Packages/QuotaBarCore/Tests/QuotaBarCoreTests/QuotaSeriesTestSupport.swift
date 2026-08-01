import Foundation

@testable import QuotaBarCore

private nonisolated(unsafe) let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

enum TestSeries {
    static func instant(_ iso: String) -> Date {
        guard let date = isoFormatter.date(from: iso) else {
            fatalError("instante de teste inválido: \(iso)")
        }
        return date
    }

    static func percent(_ value: String) -> Utilization {
        guard let decimal = Decimal(string: value), let utilization = Utilization(originPercent: decimal) else {
            fatalError("percentual de teste inválido: \(value)")
        }
        return utilization
    }

    static func sample(
        at iso: String,
        sequence: UInt64,
        fiveHour: String? = nil,
        sevenDay: String? = nil,
        fiveHourResetsAt: String? = nil,
        sevenDayResetsAt: String? = nil,
        source: QuotaSource = .primaryProbe
    ) -> QuotaSample {
        QuotaSample(
            readAt: instant(iso),
            readSequence: sequence,
            fiveHour: fiveHour.map(percent),
            sevenDay: sevenDay.map(percent),
            fiveHourResetsAt: fiveHourResetsAt.map(instant),
            sevenDayResetsAt: sevenDayResetsAt.map(instant),
            source: source
        )
    }

    static func series(_ samples: [QuotaSample]) -> QuotaSampleSeries {
        QuotaSampleSeries(samples)
    }

    static func fiveHourSeries(
        _ readings: [(at: String, percent: String)],
        resetsAt: String? = nil
    ) -> QuotaSampleSeries {
        series(
            readings.enumerated().map { index, reading in
                sample(
                    at: reading.at,
                    sequence: UInt64(index + 1),
                    fiveHour: reading.percent,
                    fiveHourResetsAt: resetsAt
                )
            }
        )
    }

    static func sevenDaySeries(
        _ readings: [(at: String, percent: String)],
        resetsAt: String? = nil
    ) -> QuotaSampleSeries {
        series(
            readings.enumerated().map { index, reading in
                sample(
                    at: reading.at,
                    sequence: UInt64(index + 1),
                    sevenDay: reading.percent,
                    sevenDayResetsAt: resetsAt
                )
            }
        )
    }

    static func succeededState(_ snapshot: QuotaSnapshot) -> QuotaState {
        QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .succeeded(at: snapshot.readAt),
            cycle: nil,
            maxIdleCadenceSinceReading: .seconds(180),
            source: snapshot.source
        )
    }

    static func failedState(_ reason: FailureReason, keeping snapshot: QuotaSnapshot?) -> QuotaState {
        QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .failed(reason),
            cycle: nil,
            maxIdleCadenceSinceReading: .seconds(180),
            source: snapshot?.source
        )
    }
}

extension Projection {
    var isInsufficient: Bool {
        if case .insufficientSample = self { return true }
        return false
    }

    var insufficiency: InsufficiencyReason? {
        if case let .insufficientSample(reason) = self { return reason }
        return nil
    }

    var unavailability: UnavailabilityReason? {
        if case let .unavailable(reason) = self { return reason }
        return nil
    }

    var isExhausted: Bool {
        if case .exhausted = self { return true }
        return false
    }

    var exhaustedResetsAt: Date? {
        if case let .exhausted(resetsAt) = self { return resetsAt }
        return nil
    }

    var projectedExhaustion: ProjectedExhaustion? {
        if case let .projected(exhaustion) = self { return exhaustion }
        return nil
    }

    var resetPrecedingExhaustion: Date? {
        if case let .resetsBeforeExhausting(resetsAt, _, _) = self { return resetsAt }
        return nil
    }

    var hasNoObservedConsumption: Bool {
        if case .noObservedConsumption = self { return true }
        return false
    }
}
