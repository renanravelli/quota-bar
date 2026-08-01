import Foundation
import Testing

@testable import QuotaBarCore

private struct ReanchoringPath: Sendable {
    let name: String
    let reanchoredAt: Date
    let apply: @Sendable (inout ProbePlanner, Date) -> Void
}

private enum Reanchored {
    static let readAt = TestSnapshot.readAt
    static let interval: Duration = .seconds(180)

    static let withoutANewReading: [ReanchoringPath] = [
        ReanchoringPath(name: "falha tolerada mantendo a cadência", reanchoredAt: readAt.addingTimeInterval(180)) {
            $0.recordFailure(reaction: .keepCadence, jitter: 0, at: $1)
        },
        ReanchoringPath(name: "falha tolerada ampliando a cadência", reanchoredAt: readAt.addingTimeInterval(180)) {
            $0.recordFailure(reaction: .widenCadence, jitter: 0.5, at: $1)
        },
        ReanchoringPath(name: "estrangulamento", reanchoredAt: readAt.addingTimeInterval(180)) {
            $0.recordThrottling(retryAfter: .seconds(600), jitter: 0, at: $1)
        },
        ReanchoringPath(name: "retomada após suspensão", reanchoredAt: readAt.addingTimeInterval(3_600)) {
            $0.resume(nextProbeAt: $1.addingTimeInterval(180), at: $1)
        },
        ReanchoringPath(name: "tentativa não alcançada", reanchoredAt: readAt.addingTimeInterval(600)) {
            $0.recordUnreachedAttempt(retryAt: $1.addingTimeInterval(180), decidedAt: $1)
        }
    ]

    static func plannerAfterAReading() -> ProbePlanner {
        var planner = ProbePlanner(startingAt: readAt)
        planner.recordReading(utilizationChanged: true, at: readAt)
        return planner
    }

    static func state(of planner: ProbePlanner) -> QuotaState {
        QuotaState(
            credentialPresent: true,
            snapshot: TestSnapshot.make(fiveHourPercent: "40", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: .succeeded(at: readAt),
            cycle: planner.cycle,
            maxIdleCadenceSinceReading: planner.maxIdleCadenceSinceReading,
            source: .primaryProbe
        )
    }

    static func display(of planner: ProbePlanner, at now: Date) -> CadenceDisplay? {
        var latch = DeferralLatch()
        let state = state(of: planner)

        return CadenceDisplayPolicy.display(
            for: state.cadence(at: now, latch: &latch),
            expectedReadingAt: state.cycle?.expectedReadingAt,
            now: now
        )
    }

    static func anchorReconstructedFromTheReading(of planner: ProbePlanner) -> Date {
        readAt.adding(planner.cycle.cadence.interval)
    }
}

@Suite("Âncora do preenchimento da barra de cadência")
struct CadenceAnchorTests {
    @Test("QB-APP-002 REQ-11 e ADR-010: um ciclo reancorado sem leitura nova nasce vazio, e não saturado")
    func aCycleReanchoredWithoutANewReadingIsBornEmpty() throws {
        for path in Reanchored.withoutANewReading {
            var planner = Reanchored.plannerAfterAReading()
            path.apply(&planner, path.reanchoredAt)

            #expect(
                planner.cycle.expectedReadingAt != Reanchored.anchorReconstructedFromTheReading(of: planner),
                "\(path.name): a fixture fez os dois instantes coincidirem, e o teste não discriminaria nada"
            )
            #expect(
                try #require(Reanchored.display(of: planner, at: path.reanchoredAt)).progress == 0,
                "\(path.name): a barra afirmou progresso num ciclo que acabou de começar"
            )
        }
    }

    @Test("QB-APP-002 REQ-11: o instante publicado é o da próxima leitura, e a barra o acompanha até saturar")
    func theBarFollowsThePublishedInstantUntilItSaturates() throws {
        var planner = Reanchored.plannerAfterAReading()
        planner.recordThrottling(retryAfter: .seconds(600), jitter: 0, at: Reanchored.readAt.addingTimeInterval(180))

        let expected = planner.cycle.expectedReadingAt
        #expect(expected == planner.scheduledAt, "o ciclo publicou um instante diferente do que o planejador agendou")

        #expect(try #require(Reanchored.display(of: planner, at: expected.addingTimeInterval(-300))).progress == 0.5)
        #expect(try #require(Reanchored.display(of: planner, at: expected)).progress == 1)
        #expect(try #require(Reanchored.display(of: planner, at: expected.addingTimeInterval(600))).progress == 1)
    }

    @Test("QB-APP-002 REQ-11: pedida a leitura agora, a barra afirma que o instante previsto chegou")
    func anImmediateReadRequestSaturatesTheBar() throws {
        var planner = Reanchored.plannerAfterAReading()
        let requestedAt = Reanchored.readAt.addingTimeInterval(90)
        planner.requestImmediateRead(at: requestedAt)

        #expect(
            planner.cycle.expectedReadingAt < Reanchored.anchorReconstructedFromTheReading(of: planner),
            "a fixture não exercita a direção em que a âncora antiga atrasa a barra"
        )
        #expect(try #require(Reanchored.display(of: planner, at: requestedAt)).progress == 1)
    }

    @Test("QB-APP-002 REQ-11: depois de uma leitura nova o ciclo recomeça vazio")
    func aNewReadingStartsTheFillOver() throws {
        var planner = Reanchored.plannerAfterAReading()
        let secondReading = Reanchored.readAt.addingTimeInterval(180)
        planner.recordReading(utilizationChanged: true, at: secondReading)

        #expect(try #require(Reanchored.display(of: planner, at: secondReading)).progress == 0)
        #expect(planner.cycle.expectedReadingAt == secondReading.adding(planner.cycle.cadence.interval))
    }
}
