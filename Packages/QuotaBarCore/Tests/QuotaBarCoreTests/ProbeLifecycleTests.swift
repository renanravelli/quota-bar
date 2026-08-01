import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Ciclo de vida: suspensão, retomada e App Nap")
struct ProbeLifecycleTests {
    private static let wake = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("AC-16: a retomada da máquina devolve a cadência ao ritmo base")
    func wakeReturnsToBaseCadence() async {
        let harness = LifecycleHarness(at: Self.wake)

        let effect = await harness.deliver(.didWake)

        #expect(effect == .resumeAtBaseCadence(nextProbeAt: Self.wake, wokeAt: Self.wake))
    }

    @Test("ADR-005: nenhuma sonda enquanto a máquina dorme")
    func sleepSuspendsProbing() async {
        let harness = LifecycleHarness(at: Self.wake)

        #expect(await harness.lifecycle.allowsProbing)

        let suspension = await harness.deliver(.willSleep)
        #expect(suspension == .suspendProbing)
        #expect(await harness.lifecycle.allowsProbing == false)

        harness.clock.advance(by: 4 * 3600)
        #expect(await harness.lifecycle.allowsProbing == false)

        _ = await harness.deliver(.didWake)
        #expect(await harness.lifecycle.allowsProbing)
    }

    @Test("ADR-005: com a máquina suspensa a sonda é recusada e nada é registrado por ela")
    func aSuspendedMachineRefusesToProbe() async {
        let harness = LifecycleHarness(at: Self.wake)
        _ = await harness.deliver(.didWake)
        _ = await harness.lifecycle.probing {}
        let retryBeforeTheRefusal = await harness.lifecycle.retryAfterToleratedFailure()

        _ = await harness.deliver(.willSleep)
        harness.clock.advance(by: 10)
        let refused = await harness.lifecycle.probing { true }

        #expect(refused == nil)
        #expect(harness.activity.record.begun == 1)
        #expect(await harness.lifecycle.retryAfterToleratedFailure() == retryBeforeTheRefusal)
    }

    @Test("AC-18: a leitura de retomada respeita o piso desde a última leitura")
    func wakeProbeHonoursTheFloorSinceTheLastReading() async {
        let harness = LifecycleHarness(at: Self.wake)
        _ = await harness.lifecycle.probing {}

        harness.clock.advance(by: 10)
        let effect = await harness.deliver(.didWake)

        #expect(
            effect == .resumeAtBaseCadence(
                nextProbeAt: Self.wake.addingTimeInterval(60),
                wokeAt: Self.wake.addingTimeInterval(10)
            )
        )
    }

    @Test("AC-16: acordar com leitura antiga lê assim que a máquina volta")
    func wakeAfterALongSleepProbesImmediately() async {
        let harness = LifecycleHarness(at: Self.wake)
        _ = await harness.lifecycle.probing {}

        _ = await harness.deliver(.willSleep)
        harness.clock.advance(by: 6 * 3600)
        let effect = await harness.deliver(.didWake)

        #expect(effect == .resumeAtBaseCadence(nextProbeAt: harness.clock.now, wokeAt: harness.clock.now))
    }

    @Test("AC-34: rede indisponível na janela após o acordar não amplia a cadência")
    func networkFailureRightAfterWakeKeepsTheCadence() async {
        let harness = LifecycleHarness(at: Self.wake)
        _ = await harness.deliver(.didWake)
        _ = await harness.lifecycle.probing {}

        harness.clock.advance(by: 2)

        #expect(await harness.lifecycle.isWithinWakeTolerance())
        #expect(await harness.lifecycle.reaction(to: .communicationFailure) == .keepCadence)
    }

    @Test("AC-34: a tentativa seguinte acontece ainda dentro da janela do acordar")
    func toleratedFailureRetriesInsideTheWindow() async {
        let harness = LifecycleHarness(at: Self.wake)
        _ = await harness.deliver(.didWake)
        _ = await harness.lifecycle.probing {}

        harness.clock.advance(by: 2)
        let retry = await harness.lifecycle.retryAfterToleratedFailure()

        #expect(retry == Self.wake.addingTimeInterval(60))
        #expect(retry.map { $0 < Self.wake.addingTimeInterval(120) } == true)
    }

    @Test("AC-34: a janela do acordar excede o piso, senão nenhuma tentativa caberia nela")
    func theWakeWindowIsWiderThanTheProbeFloor() {
        #expect(ProbeLifecycle.wakeTolerance > Cadence.floor)
    }

    @Test("AC-22: passada a janela do acordar, a falha de rede volta a ampliar a cadência")
    func networkFailureOutsideTheWindowWidensAgain() async {
        let harness = LifecycleHarness(at: Self.wake)
        _ = await harness.deliver(.didWake)
        _ = await harness.lifecycle.probing {}

        harness.clock.advance(by: 121)

        #expect(await harness.lifecycle.isWithinWakeTolerance() == false)
        #expect(await harness.lifecycle.reaction(to: .communicationFailure) == .widenCadence)
        #expect(await harness.lifecycle.retryAfterToleratedFailure() == nil)
    }

    @Test("AC-28: a janela do acordar não tolera recusa de credencial")
    func theWakeWindowNeverToleratesCredentialRefusal() async {
        let harness = LifecycleHarness(at: Self.wake)
        _ = await harness.deliver(.didWake)
        _ = await harness.lifecycle.probing {}

        #expect(await harness.lifecycle.reaction(to: .credentialRejected) == .stopProbing)
        #expect(await harness.lifecycle.reaction(to: .blockedByPolicy) == .stopProbing)
    }

    @Test("ADR-005: a atividade declarada tem escopo da sonda")
    func activityIsAssertedOnlyWhileProbing() async {
        let harness = LifecycleHarness(at: Self.wake)
        let activity = harness.activity

        _ = await harness.lifecycle.probing {
            #expect(activity.held == 1)
        }

        #expect(activity.record.begun == 1)
        #expect(activity.held == 0)
    }

    @Test("ADR-005: a atividade termina mesmo quando a sonda falha")
    func activityEndsWhenTheProbeThrows() async {
        struct ProbeFailure: Error {}
        let harness = LifecycleHarness(at: Self.wake)
        var failure: (any Error)?

        do {
            _ = try await harness.lifecycle.probing { () throws -> Void in throw ProbeFailure() }
        } catch {
            failure = error
        }

        #expect(failure is ProbeFailure)
        #expect(harness.activity.held == 0)
    }

    @Test("ADR-005: nenhuma atividade é declarada fora da sonda")
    func noActivityIsAssertedOutsideProbes() async {
        let harness = LifecycleHarness(at: Self.wake)

        for _ in 0..<5 {
            _ = await harness.deliver(.willSleep)
            harness.clock.advance(by: 3600)
            _ = await harness.deliver(.didWake)
        }

        #expect(harness.activity.record.begun == 0)
    }
}
