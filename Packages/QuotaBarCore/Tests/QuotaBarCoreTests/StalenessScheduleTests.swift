import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Reavaliação por tempo e suspensão")
struct StalenessScheduleTests {
    private static let readAt = TestSnapshot.readAt

    private static func state(
        percent: String = "30",
        resetsAt: Date? = nil,
        maxIdle: Duration = .seconds(180),
        readAt: Date = StalenessScheduleTests.readAt
    ) -> QuotaState {
        QuotaState(
            credentialPresent: true,
            snapshot: TestSnapshot.make(
                fiveHourPercent: percent,
                sevenDayPercent: nil,
                bindingWindow: .window(.fiveHour),
                fiveHourResetsAt: resetsAt,
                readAt: readAt
            ),
            lastAttempt: .succeeded(at: readAt),
            cycle: TestCycle.scheduled(.seconds(180), nature: .base),
            maxIdleCadenceSinceReading: maxIdle,
            source: .primaryProbe
        )
    }

    private static func resolve(_ state: QuotaState, at now: Date, latch: inout StaleLatch) -> IndicatorState {
        IndicatorStateResolver.resolve(state: state, latch: &latch, now: now)
    }

    @Test("AC-22: retomada de suspensão marca obsolescência sem novo estado fornecido")
    func resumeFromSuspensionReevaluatesAge() {
        let state = Self.state()
        var latch = StaleLatch()

        let beforeSuspending = Self.resolve(state, at: Self.readAt.addingTimeInterval(60), latch: &latch)
        let afterResuming = Self.resolve(state, at: Self.readAt.addingTimeInterval(40 * 60), latch: &latch)

        #expect(beforeSuspending == .ready(Self.displayValue(percent: "30")))
        guard case let .stale(value) = afterResuming else {
            Issue.record("esperado stale após retomada, veio \(afterResuming)")
            return
        }
        #expect(value.utilization.truncatedPercent == 30)
        #expect(IndicatorTextFormatter.text(for: afterResuming) == "5h ~30%")
    }

    @Test("AC-23: leitura posterior ao relógio corrente tem idade zero e permanece pronta")
    func readingInTheFutureIsTreatedAsAgeZero() {
        let state = Self.state()
        var latch = StaleLatch()

        let resolved = Self.resolve(state, at: Self.readAt.addingTimeInterval(-3_600), latch: &latch)

        #expect(resolved == .ready(Self.displayValue(percent: "30")))
        #expect(!latch.isLatched)
    }

    @Test("AC-23: com leitura no futuro o próximo limiar continua no futuro")
    func futureReadingStillSchedulesForwards() {
        let now = Self.readAt.addingTimeInterval(-3_600)
        let threshold = StalenessSchedule.nextThreshold(for: Self.state(), now: now)

        #expect(threshold != nil)
        #expect(threshold! > now)
    }

    @Test("AC-13: sem reset informado, o limiar é o prazo de obsolescência da leitura")
    func thresholdIsTheStalenessDeadline() {
        let threshold = StalenessSchedule.nextThreshold(for: Self.state(), now: Self.readAt)

        #expect(threshold == Self.readAt.addingTimeInterval(600))
    }

    @Test("AC-35: com ociosidade no teto o prazo acompanha o limite de trinta minutos")
    func thresholdFollowsIdleCadence() {
        let threshold = StalenessSchedule.nextThreshold(
            for: Self.state(maxIdle: .seconds(900)),
            now: Self.readAt
        )

        #expect(threshold == Self.readAt.addingTimeInterval(1_800))
    }

    @Test("AC-14: o reset da janela exibida antecipa o limiar quando vem antes")
    func resetWinsWhenItComesFirst() {
        let reset = Self.readAt.addingTimeInterval(60)
        let threshold = StalenessSchedule.nextThreshold(
            for: Self.state(resetsAt: reset),
            now: Self.readAt
        )

        #expect(threshold == reset)
    }

    @Test("AC-13: o prazo de obsolescência vence quando o reset é mais distante")
    func stalenessDeadlineWinsWhenResetIsFurther() {
        let threshold = StalenessSchedule.nextThreshold(
            for: Self.state(resetsAt: Self.readAt.addingTimeInterval(7_200)),
            now: Self.readAt
        )

        #expect(threshold == Self.readAt.addingTimeInterval(600))
    }

    @Test("AC-22: passados todos os limiares não há mais nada a agendar")
    func noThresholdRemainsAfterAllHavePassed() {
        let threshold = StalenessSchedule.nextThreshold(
            for: Self.state(resetsAt: Self.readAt.addingTimeInterval(60)),
            now: Self.readAt.addingTimeInterval(40 * 60)
        )

        #expect(threshold == nil)
    }

    @Test("AC-8: sem leitura não há limiar de tempo a agendar")
    func noThresholdWithoutSnapshot() {
        let state = QuotaState(
            credentialPresent: true,
            snapshot: nil,
            lastAttempt: .inProgress,
            cycle: TestCycle.scheduled(.seconds(180), nature: .base),
            maxIdleCadenceSinceReading: .seconds(180),
            source: .primaryProbe
        )

        #expect(StalenessSchedule.nextThreshold(for: state, now: Self.readAt) == nil)
    }

    @Test("AC-22: um estado novo reagenda o limiar a partir da leitura nova")
    func newStateReschedulesFromTheNewReading() {
        let later = Self.readAt.addingTimeInterval(300)
        let threshold = StalenessSchedule.nextThreshold(
            for: Self.state(readAt: later),
            now: later
        )

        #expect(threshold == later.addingTimeInterval(600))
    }

    @Test("REQ-12: nada muda entre agora e o limiar, então um único disparo basta")
    func verdictIsConstantUntilTheThreshold() {
        let state = Self.state()
        let threshold = StalenessSchedule.nextThreshold(for: state, now: Self.readAt)!

        for offset in stride(from: 0.0, to: 600.0, by: 7.0) {
            var latch = StaleLatch()
            let resolved = Self.resolve(state, at: Self.readAt.addingTimeInterval(offset), latch: &latch)
            #expect(resolved.isReady, "estado mudou antes do limiar, em +\(offset)s")
        }

        var latchAtThreshold = StaleLatch()
        let justAfter = Self.resolve(state, at: threshold.addingTimeInterval(1), latch: &latchAtThreshold)

        #expect(!justAfter.isReady)
    }

    private static func displayValue(percent: String) -> DisplayValue {
        let utilization = TestSnapshot.utilization(percent)!
        return DisplayValue(
            selection: .reportedByOrigin(.fiveHour),
            utilization: utilization,
            band: ConsumptionBand(utilization: utilization)
        )
    }
}

private extension IndicatorState {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}
