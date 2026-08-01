import Foundation
import QuotaBarCore

private final class RotatingFixtureProvider: QuotaStateProviding {
    let states: AsyncStream<QuotaState>

    private let continuation: AsyncStream<QuotaState>.Continuation

    init(rotation: [QuotaState], every interval: Duration) {
        let (stream, continuation) = AsyncStream.makeStream(of: QuotaState.self)
        states = stream
        self.continuation = continuation

        Task { [continuation] in
            while !Task.isCancelled {
                for state in rotation {
                    continuation.yield(state)
                    try? await Task.sleep(for: interval)
                }
            }
        }
    }

    func refreshNow() async {}

    func setViewerObserving(_ observing: Bool) async {}
}

enum ProviderFactory {
    static let isFixtureFed = true

    static func make() -> any QuotaStateProviding {
        RotatingFixtureProvider(rotation: rotation, every: .seconds(4))
    }

    private static var rotation: [QuotaState] {
        [
            .unconfigured,
            reading(percent: "50", source: .primaryProbe, readSequence: 1),
            reading(percent: "80", source: .primaryProbe, readSequence: 2),
            reading(percent: "95", source: .primaryProbe, readSequence: 3),
            reading(percent: "100", source: .primaryProbe, readSequence: 4),
            reading(percent: "60", source: .contingencyStatusLine, readSequence: 5),
            failing
        ]
    }

    private static var failing: QuotaState {
        QuotaState(
            credentialPresent: true,
            snapshot: nil,
            lastAttempt: .failed(.credentialExpired),
            cycle: CadenceCycle(
                id: 1,
                cadence: ScheduledCadence(interval: .seconds(600), nature: .widenedByFailure)!,
                deferralDeadline: .distantFuture
            ),
            maxIdleCadenceSinceReading: ScheduledCadence.floor,
            source: .primaryProbe
        )
    }

    private static func reading(percent: String, source: QuotaSource, readSequence: UInt64) -> QuotaState {
        let now = Date()
        let snapshot = QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: Utilization(originPercent: Decimal(string: percent) ?? 0),
                resetsAt: now.addingTimeInterval(3_600),
                status: .allowed
            ),
            sevenDay: WindowReading(
                utilization: Utilization(originPercent: 41),
                resetsAt: now.addingTimeInterval(86_400),
                status: .allowed
            ),
            overallStatus: .allowed,
            nextResetAt: now.addingTimeInterval(3_600),
            bindingWindow: source == .primaryProbe ? .window(.fiveHour) : nil,
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: readSequence,
            readAt: now,
            source: source
        )

        return QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .succeeded(at: now),
            cycle: CadenceCycle(
                id: readSequence,
                cadence: ScheduledCadence(interval: .seconds(180), nature: .base)!,
                deferralDeadline: now.addingTimeInterval(270)
            ),
            maxIdleCadenceSinceReading: .seconds(180),
            source: source
        )
    }
}
