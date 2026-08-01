import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Prazo do ciclo — apertar, nunca afrouxar")
struct CycleDeadlineTests {
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    private static func second(_ value: Int) -> Date {
        start.addingTimeInterval(TimeInterval(value))
    }

    private static func isDeferred(_ planner: ProbePlanner, at now: Date) -> Bool {
        now > planner.cycle.deferralDeadline
    }

    private static func plannerHoldingItsFirstReading() -> ProbePlanner {
        var planner = ProbePlanner(startingAt: start)
        planner.recordReading(utilizationChanged: true, at: start)
        return planner
    }

    private static func firstDeferredSecond(openingThePanelEvery openings: Int?) -> Int? {
        var planner = plannerHoldingItsFirstReading()

        for elapsed in 1...1_800 {
            if let openings, elapsed % openings == 0 {
                planner.setViewerObserving(true, at: second(elapsed))
                planner.setViewerObserving(false, at: second(elapsed))
            }
            if isDeferred(planner, at: second(elapsed)) { return elapsed }
        }
        return nil
    }

    @Test("AC-55: olhar a cada 4 minutos não empurra a entrada na condição para frente")
    func lookingNeverPostponesTheEntrance() throws {
        let untouched = try #require(Self.firstDeferredSecond(openingThePanelEvery: nil))
        let watched = try #require(Self.firstDeferredSecond(openingThePanelEvery: 240))

        #expect(watched == untouched)
        #expect(untouched <= 1_800)
    }

    @Test("AC-53: reagendar por chegada de observador não apaga um atraso vigente")
    func reschedulingNeverErasesAStandingDeferral() {
        var planner = ProbePlanner(startingAt: Self.start)
        planner.recordReading(utilizationChanged: false, at: Self.start)

        let deferredAt = Self.second(1_500)
        #expect(Self.isDeferred(planner, at: deferredAt))

        planner.setViewerObserving(true, at: deferredAt)

        #expect(Self.isDeferred(planner, at: deferredAt))
        #expect(planner.cadence.nature == .base)
    }

    @Test("AC-54: entrar e sair dez vezes não faz a condição oscilar nem provoca leitura")
    func enteringAndLeavingNeverOscillatesTheCondition() {
        var planner = ProbePlanner(startingAt: Self.start)
        planner.recordReading(utilizationChanged: false, at: Self.start)
        let lastProbe = planner.lastProbeAt

        var verdicts: [Bool] = []
        for step in 0..<10 {
            let now = Self.second(1_500 + step * 30)
            planner.setViewerObserving(true, at: now)
            verdicts.append(Self.isDeferred(planner, at: now))
            planner.setViewerObserving(false, at: now.addingTimeInterval(5))
            verdicts.append(Self.isDeferred(planner, at: now.addingTimeInterval(5)))
        }

        #expect(verdicts.allSatisfy { $0 })
        #expect(planner.lastProbeAt == lastProbe)
    }

    @Test("AC-48: a chegada da leitura encerra o ciclo e o seguinte nasce pontual")
    func aReadingEndsTheCycle() {
        var planner = Self.plannerHoldingItsFirstReading()
        let late = Self.second(400)
        #expect(Self.isDeferred(planner, at: late))
        let deferredCycle = planner.cycle.id

        planner.recordReading(utilizationChanged: true, at: late)

        #expect(planner.cycle.id != deferredCycle)
        #expect(Self.isDeferred(planner, at: late) == false)
        #expect(planner.cadence.nature == .base)
    }

    @Test("AC-49: a falha que amplia a cadência encerra o ciclo e não vira adiamento")
    func aWideningFailureEndsTheCycle() {
        var planner = Self.plannerHoldingItsFirstReading()
        let late = Self.second(400)
        #expect(Self.isDeferred(planner, at: late))

        planner.recordFailure(reaction: .widenCadence, jitter: 1, at: late)

        #expect(Self.isDeferred(planner, at: late) == false)
        #expect(planner.cadence.nature == .widenedByFailure)
    }

    @Test("AC-50: a falha tolerada após a retomada encerra o ciclo sem ampliar a cadência")
    func aToleratedFailureEndsTheCycleWithoutWidening() {
        var planner = Self.plannerHoldingItsFirstReading()
        let late = Self.second(400)
        #expect(Self.isDeferred(planner, at: late))

        planner.recordFailure(reaction: .keepCadence, jitter: 1, at: late)

        #expect(Self.isDeferred(planner, at: late) == false)
        #expect(planner.cadence.nature == .base)
        #expect(planner.cadence.interval == ProbePlanner.baseInterval)
    }

    @Test("AC-51: a retomada de suspensão encerra a condição e devolve o ritmo base")
    func wakingEndsTheCycle() {
        var planner = Self.plannerHoldingItsFirstReading()
        let wake = Self.second(8 * 3_600)
        #expect(Self.isDeferred(planner, at: Self.second(400)))

        planner.resume(nextProbeAt: wake, at: wake)

        #expect(Self.isDeferred(planner, at: wake) == false)
        #expect(planner.cadence.nature == .base)
    }

    @Test("AC-52: depois de acordar, o atraso volta a valer contado da âncora nova")
    func deferralHoldsAgainAfterWaking() {
        var planner = Self.plannerHoldingItsFirstReading()
        let wake = Self.second(8 * 3_600)
        planner.resume(nextProbeAt: wake, at: wake)

        #expect(Self.isDeferred(planner, at: wake.addingTimeInterval(240)) == false)
        #expect(Self.isDeferred(planner, at: wake.addingTimeInterval(300)))
    }

    @Test("§9.4: a pendência de Claude Code inicia ciclo, e a recuperação não nasce declarando adiamento")
    func aPendencyStartsACycleSoRecoveryIsNeverBornDeferred() {
        var planner = Self.plannerHoldingItsFirstReading()

        for minute in stride(from: 3, through: 60, by: 3) {
            let now = Self.second(minute * 60)
            planner.recordUnreachedAttempt(retryAt: now.addingTimeInterval(180), decidedAt: now)
            #expect(Self.isDeferred(planner, at: now) == false, "a pendência nasceu adiada no minuto \(minute)")
        }

        #expect(planner.lastProbeAt == Self.start)
        #expect(Self.isDeferred(planner, at: Self.second(60 * 60)) == false)
    }

    @Test("§9.5: o prazo do ciclo é sempre posterior ao instante agendado")
    func theDeadlineIsAlwaysLaterThanTheScheduledInstant() {
        var planner = ProbePlanner(startingAt: Self.start)
        var elapsed = 0
        var violations: [Int] = []

        for step in 0..<60 {
            elapsed += 30 + step * 7

            switch step % 5 {
            case 0: planner.recordReading(utilizationChanged: step % 2 == 0, at: Self.second(elapsed))
            case 1: planner.setViewerObserving(true, at: Self.second(elapsed))
            case 2: planner.setViewerObserving(false, at: Self.second(elapsed))
            case 3: planner.recordFailure(reaction: .widenCadence, jitter: 0.5, at: Self.second(elapsed))
            default: planner.resume(nextProbeAt: Self.second(elapsed + 60), at: Self.second(elapsed))
            }

            if planner.cycle.deferralDeadline <= planner.scheduledAt { violations.append(step) }
        }

        #expect(violations.isEmpty, "o prazo não superou o instante agendado nos passos \(violations)")
    }

    @Test("§9.5: o prazo do ciclo nunca aumenta enquanto o ciclo é o mesmo")
    func theDeadlineNeverGrowsWithinACycle() {
        var planner = Self.plannerHoldingItsFirstReading()
        var deadlines = [planner.cycle.deferralDeadline]

        for step in 1...20 {
            planner.setViewerObserving(true, at: Self.second(step * 10))
            planner.reschedule(at: Self.second(step * 10 + 900), decidedAt: Self.second(step * 10 + 1))
            deadlines.append(planner.cycle.deferralDeadline)
            #expect(planner.cycle.id == 2)
        }

        #expect(zip(deadlines, deadlines.dropFirst()).allSatisfy { $1 <= $0 })
    }

    @Test("AC-58: dobrado o limiar na fonte única, o prazo do ciclo acompanha")
    func theCycleDeadlineFollowsTheInjectedThreshold() {
        let doubled = DeferralPolicy(tolerance: DeferralPolicy.standard.tolerance * 2)
        var planner = ProbePlanner(startingAt: Self.start, policy: doubled)
        planner.recordReading(utilizationChanged: true, at: Self.start)

        #expect(planner.cycle.deferralDeadline == Self.second(360))
        #expect(Self.isDeferred(planner, at: Self.second(300)) == false)
        #expect(Self.isDeferred(planner, at: Self.second(400)))
    }
}
