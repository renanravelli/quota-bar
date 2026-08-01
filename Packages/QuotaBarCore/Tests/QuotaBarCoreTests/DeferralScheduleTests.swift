import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Limiar de adiamento do ciclo corrente")
struct DeferralScheduleTests {
    private static let readAt = TestSnapshot.readAt

    private static func state(deadline: Date?, readAt: Date = DeferralScheduleTests.readAt) -> QuotaState {
        QuotaState(
            credentialPresent: true,
            snapshot: TestSnapshot.make(
                fiveHourPercent: "30",
                sevenDayPercent: nil,
                bindingWindow: .window(.fiveHour),
                readAt: readAt
            ),
            lastAttempt: .succeeded(at: readAt),
            cycle: deadline.map { TestCycle.scheduled(.seconds(180), deferralDeadline: $0) },
            maxIdleCadenceSinceReading: .seconds(180),
            source: .primaryProbe
        )
    }

    @Test("AC-45: o próximo limiar é o prazo publicado do ciclo")
    func theNextThresholdIsThePublishedDeadline() {
        let deadline = Self.readAt.addingTimeInterval(270)

        #expect(DeferralSchedule.nextThreshold(for: Self.state(deadline: deadline), now: Self.readAt) == deadline)
    }

    @Test("AC-45: depois de vencido, o prazo não é mais um limiar a esperar")
    func aPassedDeadlineIsNoLongerAThreshold() {
        let deadline = Self.readAt.addingTimeInterval(270)
        let state = Self.state(deadline: deadline)

        #expect(DeferralSchedule.nextThreshold(for: state, now: deadline) == nil)
        #expect(DeferralSchedule.nextThreshold(for: state, now: deadline.addingTimeInterval(1)) == nil)
    }

    @Test("AC-41: sem ciclo agendado não há limiar a esperar")
    func noCycleMeansNoThreshold() {
        #expect(DeferralSchedule.nextThreshold(for: Self.state(deadline: nil), now: Self.readAt) == nil)
    }

    @Test("AC-45: o limiar é lido do prazo publicado, não recalculado do intervalo")
    func theThresholdComesFromThePublishedDeadlineAlone() {
        let farDeadline = Self.readAt.addingTimeInterval(86_400)

        #expect(DeferralSchedule.nextThreshold(for: Self.state(deadline: farDeadline), now: Self.readAt) == farDeadline)
    }
}
