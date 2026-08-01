import Testing

@testable import QuotaBarCore

@Suite("Política de obsolescência")
struct StalenessPolicyTests {
    @Test(
        "AC-38: tabela de unidade do limite de obsolescência",
        arguments: [
            (age: Duration.seconds(9 * 60), maxIdle: Duration.seconds(3 * 60), expected: false),
            (age: Duration.seconds(11 * 60), maxIdle: Duration.seconds(3 * 60), expected: true),
            (age: Duration.seconds(28 * 60), maxIdle: Duration.seconds(15 * 60), expected: false),
            (age: Duration.seconds(31 * 60), maxIdle: Duration.seconds(15 * 60), expected: true),
            (age: Duration.seconds(39 * 60), maxIdle: Duration.seconds(60 * 60), expected: false),
            (age: Duration.seconds(41 * 60), maxIdle: Duration.seconds(60 * 60), expected: true)
        ]
    )
    func unitTableOfStaleness(age: Duration, maxIdle: Duration, expected: Bool) {
        #expect(StalenessPolicy.isStale(age: age, maxIdleCadenceSinceReading: maxIdle) == expected)
    }

    @Test("AC-38: o piso de 10 minutos vale enquanto o dobro da cadência for menor")
    func limitIsClampedByFloor() {
        #expect(StalenessPolicy.limit(maxIdleCadenceSinceReading: .seconds(60)) == .seconds(600))
        #expect(StalenessPolicy.limit(maxIdleCadenceSinceReading: .seconds(180)) == .seconds(600))
        #expect(StalenessPolicy.limit(maxIdleCadenceSinceReading: .seconds(300)) == .seconds(600))
    }

    @Test("AC-38: acima do piso o limite é o dobro da maior cadência de ociosidade")
    func limitIsTwiceTheIdleCadence() {
        #expect(StalenessPolicy.limit(maxIdleCadenceSinceReading: .seconds(360)) == .seconds(720))
        #expect(StalenessPolicy.limit(maxIdleCadenceSinceReading: .seconds(900)) == .seconds(1_800))
    }

    @Test("AC-38: o teto de 40 minutos é salvaguarda e não é ultrapassado")
    func limitIsClampedByCeiling() {
        #expect(StalenessPolicy.limit(maxIdleCadenceSinceReading: .seconds(1_200)) == .seconds(2_400))
        #expect(StalenessPolicy.limit(maxIdleCadenceSinceReading: .seconds(3_600)) == .seconds(2_400))
        #expect(StalenessPolicy.ceiling == .seconds(2_400))
        #expect(StalenessPolicy.floor == .seconds(600))
    }

    @Test("AC-38: a idade exatamente no limite ainda não é obsoleta")
    func ageExactlyAtTheLimitIsNotStale() {
        #expect(!StalenessPolicy.isStale(age: .seconds(600), maxIdleCadenceSinceReading: .seconds(180)))
        #expect(StalenessPolicy.isStale(age: .seconds(601), maxIdleCadenceSinceReading: .seconds(180)))
        #expect(!StalenessPolicy.isStale(age: .seconds(1_800), maxIdleCadenceSinceReading: .seconds(900)))
        #expect(StalenessPolicy.isStale(age: .seconds(1_801), maxIdleCadenceSinceReading: .seconds(900)))
    }

    @Test("AC-45: o limite depende da ociosidade, nunca do intervalo ampliado por falha")
    func limitIgnoresFailureWidenedInterval() {
        let baseOnly = StalenessPolicy.limit(maxIdleCadenceSinceReading: .seconds(180))

        #expect(baseOnly == .seconds(600))
        #expect(StalenessPolicy.isStale(age: .seconds(11 * 60), maxIdleCadenceSinceReading: .seconds(180)))
    }
}
