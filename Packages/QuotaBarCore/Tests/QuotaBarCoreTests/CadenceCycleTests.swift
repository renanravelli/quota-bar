import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Ciclo de cadência publicado")
struct CadenceCycleTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static func state(cycle: CadenceCycle?) -> QuotaState {
        QuotaState(
            credentialPresent: cycle != nil,
            snapshot: nil,
            cycle: cycle,
            maxIdleCadenceSinceReading: ScheduledCadence.floor,
            source: cycle == nil ? nil : .primaryProbe
        )
    }

    @Test("o que se agenda tem três naturezas, e adiada pelo sistema não é uma delas")
    func whatIsScheduledCannotSayDeferred() {
        #expect(ScheduledNature.allCases.count == 3)
        #expect(Set(ScheduledNature.allCases.map(\.observed)).count == 3)
        #expect(!ScheduledNature.allCases.map(\.observed).contains(.deferredBySystem))
    }

    @Test("há um único lugar no estado que fala do ciclo corrente")
    func theStateSpeaksOfTheCycleInExactlyOnePlace() {
        let published = Self.state(cycle: TestCycle.scheduled())
        let children = Mirror(reflecting: published).children.compactMap(\.label)

        #expect(children.filter { $0 == "cycle" }.count == 1)
        #expect(!children.contains("cadence"))
        #expect(!children.contains("isDeferred"))
        #expect(!children.contains("deferralDeadline"))
    }

    @Test("com ciclo agendado a condição existe e nasce não em atraso")
    func theCycleStartsPunctual() throws {
        var planner = ProbePlanner(startingAt: Self.now)
        planner.recordReading(utilizationChanged: true, at: Self.now)

        let cycle = try #require(Self.state(cycle: planner.cycle).cycle)

        #expect(cycle.deferralDeadline > Self.now)
        #expect(cycle.deferralDeadline > planner.scheduledAt)
        #expect(cycle.cadence.nature == .base)
    }

    @Test("sem ciclo agendado, o estado não afirma cadência alguma")
    func noCycleMeansNoAffirmation() {
        #expect(Self.state(cycle: nil).cycle == nil)
        #expect(QuotaState.unconfigured.cycle == nil)
    }

    @Test("o que não é ociosidade não eleva a maior cadência de ociosidade")
    func onlyIdlenessRaisesTheIdleMaximum() {
        var maximum = MaxIdleCadenceSinceReading(
            atReading: ScheduledCadence(interval: .seconds(180), nature: .base)!
        )

        maximum.observe(ScheduledCadence(interval: .seconds(1_800), nature: .widenedByFailure)!)
        #expect(maximum.value == .seconds(180))

        maximum.observe(ScheduledCadence(interval: .seconds(900), nature: .idle)!)
        #expect(maximum.value == .seconds(900))

        #expect(ScheduledNature.allCases.filter(\.raisesMaxIdleCadence) == [.base, .idle])
    }

    @Test("o piso de 60 segundos recusa qualquer cadência agendada menor")
    func theScheduledFloorRefusesAnythingBelowSixtySeconds() {
        #expect(ScheduledCadence.floor == .seconds(60))
        #expect(ScheduledCadence(interval: .seconds(59), nature: .base) == nil)
        #expect(ScheduledCadence(interval: .zero, nature: .idle) == nil)
        #expect(ScheduledCadence(interval: .seconds(60), nature: .base)?.interval == .seconds(60))
    }
}
