import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Reagendamento por mudança de cadência")
struct ProbeScheduleTests {
    private static let lastProbe = Date(timeIntervalSince1970: 1_700_000_000)
    private static let base = Duration.seconds(180)
    private static let idle = Duration.seconds(900)

    private static func minute(_ value: Double) -> Date {
        lastProbe.addingTimeInterval(value * 60)
    }

    @Test("AC-17: observador entrando tarde não antecipa a leitura agendada")
    func lateViewerDoesNotAdvanceTheProbe() {
        let arrival = Self.minute(14)

        let next = ProbeSchedule.next(
            scheduled: Self.minute(15),
            now: arrival,
            newCadence: Self.base,
            lastProbeAt: Self.lastProbe
        )

        #expect(next == Self.minute(15))
        #expect(next > arrival)
    }

    @Test("AC-18: observador entrando cedo acelera até o piso, e não além")
    func earlyViewerAcceleratesWithinTheFloor() {
        let next = ProbeSchedule.next(
            scheduled: Self.minute(15),
            now: Self.minute(1),
            newCadence: Self.base,
            lastProbeAt: Self.lastProbe
        )

        #expect(next == Self.minute(4))
        #expect(next >= Self.lastProbe.addingTimeInterval(60))
    }

    @Test("AC-18: o piso desde a última leitura vence um agendamento mais próximo")
    func floorSinceLastProbeWins() {
        let next = ProbeSchedule.next(
            scheduled: Self.lastProbe.addingTimeInterval(10),
            now: Self.lastProbe.addingTimeInterval(5),
            newCadence: Cadence.floor,
            lastProbeAt: Self.lastProbe
        )

        #expect(next == Self.lastProbe.addingTimeInterval(60))
    }

    @Test("AC-19: entrar e sair dez vezes não move o instante nem acumula leituras")
    func repeatedObservationNeverAmplifies() {
        var scheduled = Self.minute(4)
        var instants: [Date] = []
        var probesDue = 0

        for step in 0..<10 {
            let entrance = Self.minute(1 + Double(step) * 0.2)
            scheduled = ProbeSchedule.next(
                scheduled: scheduled,
                now: entrance,
                newCadence: Self.base,
                lastProbeAt: Self.lastProbe
            )
            instants.append(scheduled)
            if scheduled <= entrance { probesDue += 1 }

            let exit = entrance.addingTimeInterval(6)
            scheduled = ProbeSchedule.next(
                scheduled: scheduled,
                now: exit,
                newCadence: Self.idle,
                lastProbeAt: Self.lastProbe
            )
            instants.append(scheduled)
            if scheduled <= exit { probesDue += 1 }
        }

        #expect(instants.count == 20)
        #expect(Set(instants) == [Self.minute(4)])
        #expect(probesDue == 0)
    }

    @Test("AC-11: alargar a cadência não empurra uma leitura já agendada para depois")
    func wideningNeverPostponesAScheduledProbe() {
        let next = ProbeSchedule.next(
            scheduled: Self.minute(3),
            now: Self.minute(1),
            newCadence: Self.idle,
            lastProbeAt: Self.lastProbe
        )

        #expect(next == Self.minute(3))
    }

    @Test("AC-17: sem leitura agendada, o instante nasce da cadência corrente")
    func firstScheduleComesFromTheCurrentCadence() {
        let next = ProbeSchedule.next(
            scheduled: nil,
            now: Self.minute(1),
            newCadence: Self.base,
            lastProbeAt: Self.lastProbe
        )

        #expect(next == Self.minute(4))
    }
}
