import Foundation
import Testing

@testable import QuotaBarCore

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private struct CadenceStep {
    let interval: Duration
    let nature: ScheduledNature
}

@Suite("Trava de obsolescência")
struct StaleLatchTests {
    private static let readAt = TestSnapshot.readAt
    private static let idleIntervals = [60, 180, 300, 600, 900]
    private static let failureIntervals = [300, 600, 1_200, 1_800]

    private static func at(_ seconds: TimeInterval) -> Date {
        readAt.addingTimeInterval(seconds)
    }

    private static func resolve(
        _ snapshot: QuotaSnapshot,
        latch: inout StaleLatch,
        now: Date
    ) -> IndicatorState {
        let state = QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .succeeded(at: snapshot.readAt),
            cycle: TestCycle.scheduled(.seconds(180), nature: .base),
            maxIdleCadenceSinceReading: .seconds(180),
            source: .primaryProbe
        )
        return IndicatorStateResolver.resolve(state: state, latch: &latch, now: now)
    }

    private static let halfOfTheFiveHourWindow = DisplayValue(
        selection: .reportedByOrigin(.fiveHour),
        utilization: Utilization(originPercent: 50)!,
        band: .normal
    )

    @Test("AC-44: uma vez marcada, a trava só sai com leitura nova")
    func latchHoldsUntilANewReading() {
        var latch = StaleLatch()

        let whileRecent = latch.evaluate(
            readSequence: 1, readingAt: Self.readAt, now: Self.at(300),
            maxIdleCadenceSinceReading: .seconds(180), displayedWindowResetPassed: false
        )
        let pastTheLimit = latch.evaluate(
            readSequence: 1, readingAt: Self.readAt, now: Self.at(700),
            maxIdleCadenceSinceReading: .seconds(180), displayedWindowResetPassed: false
        )
        let withLongerToleranceAfterwards = latch.evaluate(
            readSequence: 1, readingAt: Self.readAt, now: Self.at(701),
            maxIdleCadenceSinceReading: .seconds(900), displayedWindowResetPassed: false
        )

        #expect(!whileRecent)
        #expect(pastTheLimit)
        #expect(withLongerToleranceAfterwards)
        #expect(latch.isLatched)
    }

    @Test("AC-44: uma leitura nova destrava sozinha, sem ninguém precisar lembrar")
    func newReadingUnlatchesByItself() {
        var latch = StaleLatch()

        let wentStale = latch.evaluate(
            readSequence: 1, readingAt: Self.readAt, now: Self.at(700),
            maxIdleCadenceSinceReading: .seconds(180), displayedWindowResetPassed: false
        )
        #expect(wentStale)

        let afterNewReading = latch.evaluate(
            readSequence: 2, readingAt: Self.at(700), now: Self.at(760),
            maxIdleCadenceSinceReading: .seconds(180), displayedWindowResetPassed: false
        )

        #expect(!afterNewReading)
        #expect(!latch.isLatched)
    }

    @Test("AC-44: reavaliar a mesma leitura não destrava")
    func reevaluatingTheSameReadingDoesNotUnlatch() {
        var latch = StaleLatch()

        _ = latch.evaluate(
            readSequence: 1, readingAt: Self.readAt, now: Self.at(700),
            maxIdleCadenceSinceReading: .seconds(180), displayedWindowResetPassed: false
        )
        let again = latch.evaluate(
            readSequence: 1, readingAt: Self.readAt, now: Self.at(60),
            maxIdleCadenceSinceReading: .seconds(180), displayedWindowResetPassed: false
        )

        #expect(again)
        #expect(latch.isLatched)
    }

    @Test("AC-11: reemitir a mesma leitura com instante novo não destrava")
    func reemittingTheSameReadingWithAFreshTimestampDoesNotUnlatch() {
        var latch = StaleLatch()

        let wentStale = latch.evaluate(
            readSequence: 1, readingAt: Self.readAt, now: Self.at(700),
            maxIdleCadenceSinceReading: .seconds(180), displayedWindowResetPassed: false
        )
        let afterReemission = latch.evaluate(
            readSequence: 1, readingAt: Self.at(700), now: Self.at(760),
            maxIdleCadenceSinceReading: .seconds(180), displayedWindowResetPassed: false
        )

        #expect(wentStale)
        #expect(afterReemission)
        #expect(latch.isLatched)
    }

    @Test("AC-11: reemitir o mesmo estado mantém o indicador desatualizado")
    func reemittedStateKeepsTheIndicatorStale() {
        var latch = StaleLatch()
        let reading = TestSnapshot.make(
            fiveHourPercent: "50", sevenDayPercent: nil, bindingWindow: .window(.fiveHour),
            readSequence: 1
        )
        let reemitted = TestSnapshot.make(
            fiveHourPercent: "50", sevenDayPercent: nil, bindingWindow: .window(.fiveHour),
            readSequence: 1, readAt: Self.at(700)
        )

        let wentStale = Self.resolve(reading, latch: &latch, now: Self.at(700))
        let afterReemission = Self.resolve(reemitted, latch: &latch, now: Self.at(760))

        #expect(wentStale == .stale(Self.halfOfTheFiveHourWindow))
        #expect(afterReemission == .stale(Self.halfOfTheFiveHourWindow))
    }

    @Test("AC-10: uma leitura nova com o mesmo conteúdo destrava")
    func aNewReadingWithIdenticalContentUnlatches() {
        var latch = StaleLatch()
        let reading = TestSnapshot.make(
            fiveHourPercent: "50", sevenDayPercent: nil, bindingWindow: .window(.fiveHour),
            readSequence: 1
        )
        let newReading = TestSnapshot.make(
            fiveHourPercent: "50", sevenDayPercent: nil, bindingWindow: .window(.fiveHour),
            readSequence: 2, readAt: Self.at(700)
        )

        let wentStale = Self.resolve(reading, latch: &latch, now: Self.at(700))
        let afterNewReading = Self.resolve(newReading, latch: &latch, now: Self.at(760))

        #expect(wentStale == .stale(Self.halfOfTheFiveHourWindow))
        #expect(afterNewReading == .ready(Self.halfOfTheFiveHourWindow))
    }

    @Test("AC-14: reset da janela exibida ultrapassado marca obsolescência mesmo com idade baixa")
    func passedResetLatchesRegardlessOfAge() {
        var latch = StaleLatch()

        let atReset = latch.evaluate(
            readSequence: 1, readingAt: Self.readAt, now: Self.at(1),
            maxIdleCadenceSinceReading: .seconds(180), displayedWindowResetPassed: true
        )
        let afterwards = latch.evaluate(
            readSequence: 1, readingAt: Self.readAt, now: Self.at(2),
            maxIdleCadenceSinceReading: .seconds(180), displayedWindowResetPassed: false
        )

        #expect(atReset)
        #expect(latch.isLatched)
        #expect(afterwards)
    }

    @Test("AC-23: leitura no futuro tem idade zero e não marca obsolescência")
    func readingInTheFutureIsNeverStaleByAge() {
        var latch = StaleLatch()

        let verdict = latch.evaluate(
            readSequence: 1, readingAt: Self.readAt, now: Self.at(-3_600),
            maxIdleCadenceSinceReading: .seconds(180), displayedWindowResetPassed: false
        )

        #expect(!verdict)
        #expect(StalenessPolicy.age(ofReadingAt: Self.readAt, now: Self.at(-3_600)) == .zero)
    }

    @Test("AC-45: backoff por falha não adia a marcação")
    func failureBackoffDoesNotPostponeStaleness() {
        var latch = StaleLatch()
        var maxIdle = Duration.seconds(180)
        var verdicts: [Int: Bool] = [:]

        for minute in 1...11 {
            let widenedByFailure = ScheduledCadence(interval: .seconds(min(1_800, 300 * minute)), nature: .widenedByFailure)
            if let widenedByFailure, widenedByFailure.nature != .widenedByFailure {
                maxIdle = max(maxIdle, widenedByFailure.interval)
            }

            verdicts[minute] = latch.evaluate(
                readSequence: 1,
                readingAt: Self.readAt,
                now: Self.at(TimeInterval(minute * 60)),
                maxIdleCadenceSinceReading: maxIdle,
                displayedWindowResetPassed: false
            )
        }

        #expect(maxIdle == .seconds(180))
        #expect(verdicts[9] == false)
        #expect(verdicts[10] == false)
        #expect(verdicts[11] == true)
    }

    @Test("AC-44: o veredito nunca volta de stale para ready", arguments: 1...200 as ClosedRange<UInt64>)
    func verdictNeverRegresses(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        var latch = StaleLatch()
        var elapsed = TimeInterval(0)
        var maxIdle = Duration.seconds(180)
        var alreadyStale = false

        for _ in 0..<40 {
            elapsed += TimeInterval(Int.random(in: 30...400, using: &rng))

            let step = Self.randomCadenceStep(using: &rng)
            if step.nature != .widenedByFailure {
                maxIdle = max(maxIdle, step.interval)
            }

            let verdict = latch.evaluate(
                readSequence: 1,
                readingAt: Self.readAt,
                now: Self.at(elapsed),
                maxIdleCadenceSinceReading: maxIdle,
                displayedWindowResetPassed: false
            )

            if alreadyStale {
                #expect(verdict, "veredito voltou de stale para ready na semente \(seed)")
            }
            alreadyStale = alreadyStale || verdict
        }
    }

    @Test("AC-44: sem a trava o veredito oscilaria — é isso que a trava impede", arguments: 1...200 as ClosedRange<UInt64>)
    func policyAloneWouldOscillateWhileLatchDoesNot(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        var latch = StaleLatch()
        var elapsed = TimeInterval(0)
        var maxIdle = Duration.seconds(180)
        var latchVerdicts: [Bool] = []
        var policyVerdicts: [Bool] = []

        for _ in 0..<40 {
            elapsed += TimeInterval(Int.random(in: 30...400, using: &rng))

            let step = Self.randomCadenceStep(using: &rng)
            if step.nature != .widenedByFailure {
                maxIdle = max(maxIdle, step.interval)
            }

            policyVerdicts.append(
                StalenessPolicy.isStale(
                    age: StalenessPolicy.age(ofReadingAt: Self.readAt, now: Self.at(elapsed)),
                    maxIdleCadenceSinceReading: maxIdle
                )
            )
            latchVerdicts.append(
                latch.evaluate(
                    readSequence: 1,
                    readingAt: Self.readAt,
                    now: Self.at(elapsed),
                    maxIdleCadenceSinceReading: maxIdle,
                    displayedWindowResetPassed: false
                )
            )
        }

        #expect(!Self.regresses(latchVerdicts))

        if Self.regresses(policyVerdicts) {
            #expect(latchVerdicts.last == true)
        }
    }

    @Test("AC-45: cadência ampliada por falha não eleva a maior ociosidade da leitura")
    func failureWidenedCadenceNeverRaisesIdleMaximum() {
        var maxIdle = Duration.seconds(180)
        let steps = [
            CadenceStep(interval: .seconds(1_800), nature: .widenedByFailure),
            CadenceStep(interval: .seconds(3_600), nature: .widenedByFailure),
            CadenceStep(interval: .seconds(300), nature: .idle)
        ]

        for step in steps where step.nature != .widenedByFailure {
            maxIdle = max(maxIdle, step.interval)
        }

        #expect(maxIdle == .seconds(300))
        #expect(StalenessPolicy.limit(maxIdleCadenceSinceReading: maxIdle) == .seconds(600))
    }

    private static func randomCadenceStep(using rng: inout SeededGenerator) -> CadenceStep {
        let usesFailure = Bool.random(using: &rng)
        let pool = usesFailure ? failureIntervals : idleIntervals
        let seconds = pool.randomElement(using: &rng) ?? 180
        return CadenceStep(
            interval: .seconds(seconds),
            nature: usesFailure ? .widenedByFailure : (Bool.random(using: &rng) ? .base : .idle)
        )
    }

    private static func regresses(_ verdicts: [Bool]) -> Bool {
        for (previous, current) in zip(verdicts, verdicts.dropFirst()) where previous && !current {
            return true
        }
        return false
    }
}
