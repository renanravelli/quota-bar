import Foundation
import Testing

@testable import QuotaBarCore

private enum Age {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)

    static func phrase(after elapsed: TimeInterval) -> String {
        AgeDisplay.phrase(for: StalenessPolicy.age(ofReadingAt: readAt, now: readAt.addingTimeInterval(elapsed)))
    }

    static func state() -> QuotaState {
        QuotaState(
            credentialPresent: true,
            snapshot: TestSnapshot.make(fiveHourPercent: "30", sevenDayPercent: nil, bindingWindow: nil, readAt: readAt),
            lastAttempt: .succeeded(at: readAt),
            cycle: nil,
            maxIdleCadenceSinceReading: .seconds(900),
            source: .primaryProbe
        )
    }

    static func thresholds(through horizon: TimeInterval) -> [TimeInterval] {
        var found: [TimeInterval] = []
        var cursor = readAt

        while let next = AgeDisplay.nextChange(ofReadingAt: readAt, now: cursor),
              next <= readAt.addingTimeInterval(horizon) {
            found.append(next.timeIntervalSince(readAt))
            cursor = next
        }

        return found
    }
}

@Suite("Régua da idade exibida")
struct AgeDisplayTests {
    @Test("a frase muda exatamente nos instantes que o limiar devolve")
    func thePhraseChangesExactlyAtTheThresholds() {
        var observed: [TimeInterval] = []
        var previous = Age.phrase(after: 0)

        for second in 1...7_200 {
            let phrase = Age.phrase(after: TimeInterval(second))
            if phrase != previous { observed.append(TimeInterval(second)) }
            previous = phrase
        }

        #expect(observed == Age.thresholds(through: 7_200), "a régua da frase e a do limiar divergiram")
        #expect(!observed.isEmpty)
    }

    @Test("o piso da idade não é uma fonte de 1 Hz")
    func theAgeFloorIsNotAOneHertzSource() {
        let thresholds = Age.thresholds(through: 3_600)

        #expect(thresholds.count == 60, "uma hora de painel aberto pediu \(thresholds.count) renderizações")
        #expect(zip(thresholds, thresholds.dropFirst()).allSatisfy { $1 - $0 >= 60 })
    }

    @Test("leitura no futuro envelhece a partir de zero, sem referência a tempo futuro")
    func aReadingInTheFutureAgesFromZero() {
        let before = Age.readAt.addingTimeInterval(-30)

        #expect(AgeDisplay.phrase(for: StalenessPolicy.age(ofReadingAt: Age.readAt, now: before)) == Age.phrase(after: 0))
        #expect(AgeDisplay.nextChange(ofReadingAt: Age.readAt, now: before) == Age.readAt.addingTimeInterval(60))
    }

    @Test("sem leitura não há idade a envelhecer, e nada é agendado")
    func aStateWithoutAReadingSchedulesNothing() {
        #expect(AgeSchedule.nextThreshold(for: .unconfigured, now: Age.readAt) == nil)
    }

    @Test("com leitura, o limiar do estado é o da régua")
    func theStateThresholdIsTheRulerThreshold() throws {
        let state = Age.state()
        let now = Age.readAt.addingTimeInterval(90)

        #expect(AgeSchedule.nextThreshold(for: state, now: now) == AgeDisplay.nextChange(ofReadingAt: Age.readAt, now: now))
        #expect(try #require(AgeSchedule.nextThreshold(for: state, now: now)) == Age.readAt.addingTimeInterval(120))
    }
}
