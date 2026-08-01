import Foundation
import Testing

@testable import QuotaBarCore

private enum Display {
    static let cycleStart = Date(timeIntervalSince1970: 1_700_000_000)
    static let interval: Duration = .seconds(180)
    static let expectedReadingAt = cycleStart.addingTimeInterval(180)

    static let fourNatures: [Cadence.Nature] = [.base, .idle, .widenedByFailure, .deferredBySystem]

    static func cadence(_ nature: Cadence.Nature = .base, interval: Duration = Display.interval) -> Cadence {
        guard let cadence = Cadence(interval: interval, nature: nature) else {
            fatalError("cadência de teste abaixo do piso")
        }
        return cadence
    }

    static func progress(
        _ nature: Cadence.Nature = .base,
        expectedReadingAt: Date = Display.expectedReadingAt,
        after elapsed: TimeInterval
    ) -> Double? {
        CadenceDisplayPolicy.display(
            for: cadence(nature),
            expectedReadingAt: expectedReadingAt,
            now: cycleStart.addingTimeInterval(elapsed)
        )?.progress
    }
}

@Suite("Apresentação da barra de cadência")
struct CadenceDisplayTests {
    @Test("QB-APP-002 REQ-11: dentro de um ciclo o preenchimento nunca recua")
    func theFillIsMonotonicWithinACycle() throws {
        let samples = try stride(from: 0.0, through: 360.0, by: 3.0)
            .map { try #require(Display.progress(after: $0)) }

        #expect(samples == samples.sorted(), "o preenchimento recuou com o tempo andando")
        #expect(Set(samples).count > 1, "o preenchimento não se moveu no percurso")
    }

    @Test("QB-APP-002 REQ-11: o preenchimento satura no instante previsto, não transborda e permanece cheio")
    func theFillSaturatesAtTheExpectedInstantAndStays() throws {
        #expect(try #require(Display.progress(after: 179)) < 1)
        #expect(Display.progress(after: 180) == 1)

        let afterTheInstant = try stride(from: 180.0, through: 3_600.0, by: 30.0)
            .map { try #require(Display.progress(after: $0)) }
        #expect(afterTheInstant.allSatisfy { $0 == 1 }, "o preenchimento transbordou, recomeçou ou apagou")
    }

    @Test("QB-APP-002 REQ-11: o recorte é do tipo, e não de quem constrói o valor")
    func theTypeClampsInsteadOfTrustingItsCaller() {
        #expect(CadenceDisplay(cadence: Display.cadence(), progress: 4).progress == 1)
        #expect(CadenceDisplay(cadence: Display.cadence(), progress: -3).progress == 0)
    }

    @Test("QB-APP-002 REQ-11: nenhuma das quatro naturezas altera o preenchimento")
    func theFillIsIndependentOfTheNature() throws {
        for elapsed in [0.0, 90.0, 180.0, 400.0] {
            let acrossNatures = try Display.fourNatures.map { try #require(Display.progress($0, after: elapsed)) }
            #expect(Set(acrossNatures).count == 1, "a natureza mudou o preenchimento aos \(elapsed) s")
        }
    }

    @Test("QB-APP-002 REQ-11: um ciclo que começa agora nasce com preenchimento em zero")
    func aCycleThatStartsNowIsBornEmpty() {
        let startedNow = Display.cycleStart.addingTimeInterval(600)

        #expect(
            Display.progress(expectedReadingAt: startedNow.addingTimeInterval(180), after: 600) == 0,
            "o ciclo recém-começado nasceu cheio"
        )
    }

    @Test("ADR-010: a natureza tem um lugar só, e o reforço é derivado dela")
    func theReinforcementIsDerivedFromTheOnlyNatureThereIs() {
        let displays = Display.fourNatures.map { CadenceDisplay(cadence: Display.cadence($0), progress: 0.5) }

        #expect(displays.map(\.nature) == Display.fourNatures)
        #expect(Set(displays.map(\.reinforcement)).count == 4, "duas naturezas produziram o mesmo reforço")
        #expect(displays.allSatisfy { $0.reinforcement == CadenceReinforcement($0.cadence.nature) })
        #expect(CadenceReinforcement(.base) == CadenceReinforcement.none)
    }

    @Test("QB-APP-002 REQ-11: sem cadência ou sem instante previsto não há barra a exibir")
    func thereIsNoBarWithoutACadenceOrAnExpectedInstant() {
        #expect(
            CadenceDisplayPolicy.display(
                for: nil, expectedReadingAt: Display.expectedReadingAt, now: Display.cycleStart
            ) == nil
        )
        #expect(
            CadenceDisplayPolicy.display(
                for: Display.cadence(), expectedReadingAt: nil, now: Display.cycleStart
            ) == nil
        )
    }

    @Test("QB-APP-002 REQ-18: o passo do preenchimento respeita o piso e o teto")
    func theFillPaceStaysWithinItsBounds() {
        for seconds in [60, 120, 180, 300, 900, 3_600] {
            let interval = CadenceFillPolicy.refreshInterval(for: .seconds(seconds))
            #expect(interval >= CadenceFillPolicy.fastest)
            #expect(interval <= CadenceFillPolicy.slowest)
        }

        #expect(CadenceFillPolicy.refreshInterval(for: Cadence.floor) == CadenceFillPolicy.fastest)
        #expect(CadenceFillPolicy.refreshInterval(for: .seconds(900)) == CadenceFillPolicy.slowest)
    }
}
