import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Limiar do adiamento — fonte única")
struct DeferralPolicyTests {
    private static let anchoredAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static func appointment(intended: Duration) -> ProbeAppointment {
        ProbeAppointment(
            instant: anchoredAt.addingTimeInterval(TimeInterval(intended.components.seconds)),
            anchoredAt: anchoredAt,
            intended: intended
        )
    }

    private static func second(_ value: Double) -> Date {
        anchoredAt.addingTimeInterval(value)
    }

    @Test("AC-20: o adiamento é declarado só acima do limiar")
    func deferralIsDeclaredOnlyAboveTheThreshold() {
        let cycle = Self.appointment(intended: .seconds(180))

        #expect(DeferralPolicy.standard.isDeferred(cycle, at: Self.second(300)))
        #expect(DeferralPolicy.standard.isDeferred(cycle, at: Self.second(240)) == false)
    }

    @Test("AC-20: exatamente no prazo ainda é variação normal de agendamento")
    func exactlyOnTheDeadlineIsNotDeferral() {
        let cycle = Self.appointment(intended: .seconds(180))

        #expect(DeferralPolicy.standard.isDeferred(cycle, at: Self.second(270)) == false)
        #expect(DeferralPolicy.standard.isDeferred(cycle, at: Self.second(271)))
    }

    @Test("AC-58: o veredito é o prazo, e não uma segunda conta ao lado dele")
    func theVerdictIsDefinedByTheDeadline() {
        let cycle = Self.appointment(intended: .seconds(180))
        let deadline = DeferralPolicy.standard.deadline(for: cycle)

        #expect(DeferralPolicy.standard.isDeferred(cycle, at: deadline) == false)
        #expect(DeferralPolicy.standard.isDeferred(cycle, at: deadline.addingTimeInterval(1)))
        #expect(DeferralPolicy.standard.isDeferred(cycle, at: deadline.addingTimeInterval(-1)) == false)
    }

    @Test("AC-58: dobrado o limiar no único lugar em que ele existe, prazo e veredito acompanham juntos")
    func doublingTheThresholdMovesDeadlineAndVerdictTogether() {
        let doubled = DeferralPolicy(tolerance: DeferralPolicy.standard.tolerance * 2)
        let cycle = Self.appointment(intended: .seconds(180))

        #expect(doubled.deadline(for: cycle) == Self.second(360))
        #expect(doubled.isDeferred(cycle, at: Self.second(300)) == false)
        #expect(doubled.isDeferred(cycle, at: Self.second(400)))

        #expect(DeferralPolicy.standard.isDeferred(cycle, at: Self.second(300)))
        #expect(DeferralPolicy.standard.deadline(for: cycle) == Self.second(270))
    }

    @Test("AC-58: o prazo se conta da âncora do agendamento, não da leitura anterior")
    func theDeadlineIsCountedFromTheAnchor() {
        let reanchored = ProbeAppointment(
            instant: Self.second(1_200),
            anchoredAt: Self.second(900),
            intended: .seconds(180)
        )

        #expect(DeferralPolicy.standard.deadline(for: reanchored) == Self.second(1_170))
        #expect(DeferralPolicy.standard.isDeferred(reanchored, at: Self.second(1_100)) == false)
    }

    @Test("AC-58: a composição de produção usa a política padrão e nada mais")
    func productionUsesTheStandardPolicy() {
        #expect(DeferralPolicy.standard.tolerance == 0.5)
        #expect(ProbePlanner(startingAt: Self.anchoredAt).policy == DeferralPolicy.standard)
    }
}
