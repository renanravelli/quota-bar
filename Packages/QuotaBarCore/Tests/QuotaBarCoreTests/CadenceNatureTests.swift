import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Naturezas de cadência e tolerância de obsolescência")
struct CadenceNatureTests {
    private static func cadence(_ seconds: Int, _ nature: ScheduledNature) -> ScheduledCadence {
        guard let cadence = ScheduledCadence(interval: .seconds(seconds), nature: nature) else {
            fatalError("cadência de teste abaixo do piso")
        }
        return cadence
    }

    private static let base = cadence(180, .base)
    private static let idleCeiling = cadence(900, .idle)
    private static let afterFailure = cadence(1800, .widenedByFailure)

    @Test("as quatro naturezas observáveis são distinguíveis entre si")
    func theFourObservedNaturesAreDistinct() {
        let observed: Set<Cadence.Nature> = [.base, .idle, .widenedByFailure, .deferredBySystem]

        #expect(observed.count == 4)
        #expect(Set([Self.base, Self.idleCeiling, Self.afterFailure].map(\.observed.nature)).count == 3)
        #expect(observed.subtracting([Self.base, Self.idleCeiling, Self.afterFailure].map(\.observed.nature))
            == [.deferredBySystem])
    }

    @Test("a maior cadência de ociosidade não decresce enquanto a leitura é a mesma")
    func maxIdleCadenceNeverDecreases() {
        var maxIdle = MaxIdleCadenceSinceReading(atReading: Self.base)

        maxIdle.observe(Self.idleCeiling)
        maxIdle.observe(Self.base)

        #expect(maxIdle.value == .seconds(900))
    }

    @Test("a maior cadência de ociosidade recomeça a cada leitura nova")
    func maxIdleCadenceRestartsAtEachReading() {
        var maxIdle = MaxIdleCadenceSinceReading(atReading: Self.base)
        maxIdle.observe(Self.idleCeiling)

        maxIdle.restart(atReading: Self.base)

        #expect(maxIdle.value == .seconds(180))
    }

    @Test("ampliação por falha não eleva a tolerância de obsolescência")
    func failureWideningDoesNotBuyTolerance() {
        var maxIdle = MaxIdleCadenceSinceReading(atReading: Self.base)

        maxIdle.observe(Self.afterFailure)

        #expect(maxIdle.value == .seconds(180))
        #expect(ScheduledNature.widenedByFailure.raisesMaxIdleCadence == false)
    }

    @Test("só ritmo base e ociosidade elevam a maior cadência de ociosidade")
    func onlyChosenCadencesRaiseTolerance() {
        #expect(ScheduledNature.base.raisesMaxIdleCadence)
        #expect(ScheduledNature.idle.raisesMaxIdleCadence)
    }
}
