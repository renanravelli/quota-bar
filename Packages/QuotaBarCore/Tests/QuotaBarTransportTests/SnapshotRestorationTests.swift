import CryptoKit
import Foundation
import QuotaBarCore
import Testing

@testable import QuotaBarTransport

private enum Relaunch {
    static let errorBodyCanary = "CORPO-DE-ERRO-NAO-DEVE-SER-GRAVADO"

    struct ClosedSession {
        let reading: QuotaSnapshot
        let cycle: CadenceCycle

        var stateHadTheCycleSurvived: QuotaState {
            QuotaState(
                credentialPresent: true,
                snapshot: reading,
                cycle: cycle,
                maxIdleCadenceSinceReading: ProbePlanner.baseInterval,
                source: .primaryProbe
            )
        }
    }

    static func lastSession(endedAgo: TimeInterval) -> ClosedSession {
        let readAt = ProviderHarness.start.addingTimeInterval(-endedAgo)
        var plan = ProbePlanner(startingAt: readAt)
        plan.recordReading(utilizationChanged: true, at: readAt)

        return ClosedSession(
            reading: StoredReadingFixture.snapshot(readSequence: 4, readAt: readAt),
            cycle: plan.cycle
        )
    }

    static func restorable(age: TimeInterval, readSequence: UInt64 = 4) -> InMemorySnapshotStore {
        InMemorySnapshotStore(
            StoredReadingFixture.snapshot(
                readSequence: readSequence,
                readAt: ProviderHarness.start.addingTimeInterval(-age)
            )
        )
    }

    static func indicator(of state: QuotaState, at now: Date) -> IndicatorState {
        var latch = StaleLatch()
        return IndicatorStateResolver.resolve(state: state, latch: &latch, now: now)
    }

    static func rejection(carrying canary: String) -> ProbeHTTPResponse {
        ProbeHTTPResponse(
            status: 401,
            headers: [:],
            body: Data(#"{"type":"error","error":{"message":"\#(canary)"}}"#.utf8)
        )
    }
}

@Suite("Restauração do último estado de cota no lançamento")
struct SnapshotRestorationTests {
    @Test("AC-29: o estado sobrevive ao fechamento e volta com o instante original da leitura")
    func theLastReadingSurvivesTheRelaunch() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            store: Relaunch.restorable(age: 180, readSequence: 4)
        )
        #expect(await harness.waitForPublications(1))

        let restored = try #require(harness.published.first)
        #expect(restored.snapshot?.readAt == ProviderHarness.start.addingTimeInterval(-180))
        #expect(restored.snapshot?.readSequence == 4)
        #expect(restored.credentialPresent)
    }

    @Test("AC-41: o estado restaurado, antes do primeiro ciclo, não afirma condição alguma")
    func theRestoredStateHasNoCycleYet() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            store: Relaunch.restorable(age: 180, readSequence: 4)
        )
        #expect(await harness.waitForPublications(1))

        let restored = try #require(harness.published.first)
        var latch = DeferralLatch()

        #expect(restored.snapshot != nil)
        #expect(restored.cycle == nil)
        #expect(restored.cadence(at: ProviderHarness.start, latch: &latch) == nil)
    }

    @Test("AC-29: a leitura bem-sucedida é gravada com a sequência e o instante que teve")
    func everySuccessfulReadingIsPersisted() async throws {
        let store = InMemorySnapshotStore()
        let harness = ProviderHarness(responses: [CannedResponse.reading()], store: store)
        #expect(await harness.waitForReading(sequence: 1))

        let persisted = try #require(store.current)
        #expect(persisted == harness.latest?.snapshot)
        #expect(persisted.readAt == ProviderHarness.start)
        #expect(persisted.readSequence == 1)
    }

    @Test("AC-30: relançamento com três minutos de idade não degrada o dado")
    func aThreeMinuteOldReadingIsRestoredAsFresh() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            store: Relaunch.restorable(age: 180)
        )
        #expect(await harness.waitForPublications(1))

        let restored = try #require(harness.published.first)
        #expect(restored.maxIdleCadenceSinceReading == ProbePlanner.baseInterval)

        let indicator = Relaunch.indicator(of: restored, at: ProviderHarness.start)
        if case .stale = indicator {
            Issue.record("um dado de três minutos não está desatualizado em ritmo base")
        }
    }

    @Test("AC-31: relançamento com onze minutos de idade marca o dado, sem supor ociosidade")
    func anElevenMinuteOldReadingIsRestoredAsStale() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            store: Relaunch.restorable(age: 11 * 60)
        )
        #expect(await harness.waitForPublications(1))

        let restored = try #require(harness.published.first)
        #expect(restored.maxIdleCadenceSinceReading == ProbePlanner.baseInterval)

        let indicator = Relaunch.indicator(of: restored, at: ProviderHarness.start)
        if case .stale = indicator {} else {
            Issue.record("um dado de onze minutos está desatualizado em ritmo base, e foi resolvido como \(indicator)")
        }
    }

    @Test("AC-32: sem estado restaurável o aplicativo começa vazio e segue operando")
    func nothingRestorableStillLaunches() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            store: InMemorySnapshotStore()
        )

        #expect(await harness.waitForReading(sequence: 1))

        let initial = try #require(harness.published.first)
        #expect(initial.snapshot == nil)
        #expect(initial.lastAttempt == .inProgress)
        #expect(harness.latest?.snapshot?.readSequence == 1)
    }

    @Test("AC-32: arquivo corrompido não derruba o lançamento nem vira leitura com zeros")
    func aCorruptedFileDoesNotBreakTheLaunch() async throws {
        let temporary = TemporaryStore()
        temporary.write(Data("{ \"version\": 1, \"fiveHour\":".utf8))

        let harness = ProviderHarness(responses: [CannedResponse.reading()], store: temporary.store)
        #expect(await harness.waitForReading(sequence: 1))

        #expect(harness.published.first?.snapshot == nil)
    }

    @Test("AC-32: sequência no extremo do domínio, vinda do arquivo, não derruba as leituras seguintes")
    func anExtremeStoredSequenceDoesNotBreakTheFollowingReadings() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            store: InMemorySnapshotStore(
                StoredReadingFixture.snapshot(readSequence: .max - 1, readAt: ProviderHarness.start)
            )
        )
        #expect(await harness.waitForReading(sequence: .max))
        let first = try #require(harness.latest?.snapshot?.readSequence)

        harness.clock.advance(by: 900)
        #expect(await harness.waitForState { $0.snapshot?.readSequence != first })
        let second = try #require(harness.latest?.snapshot?.readSequence)

        #expect(first == .max)
        #expect(second != first)
    }

    @Test("contratos §6: a sequência atravessa o relançamento e a primeira leitura nova destrava")
    func theReadSequenceCrossesTheRelaunch() async throws {
        let harness = ProviderHarness(
            responses: [CannedResponse.reading()],
            store: Relaunch.restorable(age: 11 * 60, readSequence: 1)
        )
        #expect(await harness.waitForReading(sequence: 2))

        let restored = try #require(harness.published.first?.snapshot)
        let fresh = try #require(harness.latest?.snapshot)

        #expect(restored.readSequence == 1)
        #expect(fresh.readSequence != restored.readSequence)

        var latch = StaleLatch()
        let latchedOnRestored = latch.evaluate(
            readSequence: restored.readSequence,
            readingAt: restored.readAt,
            now: ProviderHarness.start,
            maxIdleCadenceSinceReading: ProbePlanner.baseInterval,
            displayedWindowResetPassed: false
        )
        let latchedOnFreshReading = latch.evaluate(
            readSequence: fresh.readSequence,
            readingAt: fresh.readAt,
            now: ProviderHarness.start,
            maxIdleCadenceSinceReading: ProbePlanner.baseInterval,
            displayedWindowResetPassed: false
        )

        #expect(latchedOnRestored)
        #expect(!latchedOnFreshReading)
    }

    @Test("AC-41 e contratos §9.9: o ciclo não sobrevive ao fechamento, e o lançamento não nasce declarando adiamento")
    func theCycleDoesNotSurviveTheRelaunch() async throws {
        let temporary = TemporaryStore()
        let closed = Relaunch.lastSession(endedAgo: 6 * 3_600)
        await temporary.store.persist(closed.reading)

        let harness = ProviderHarness(responses: [CannedResponse.reading()], store: temporary.store)
        #expect(await harness.waitForPublications(1))

        let restored = try #require(harness.published.first)
        var latch = DeferralLatch()

        #expect(restored.snapshot == closed.reading)
        #expect(restored.cycle == nil)
        #expect(restored.cadence(at: ProviderHarness.start, latch: &latch) == nil)

        var latchOverTheSurvivingCycle = DeferralLatch()
        let declared = closed.stateHadTheCycleSurvived.cadence(
            at: ProviderHarness.start,
            latch: &latchOverTheSurvivingCycle
        )
        #expect(declared?.nature == .deferredBySystem)
    }

    @Test("AC-33: o arquivo gravado não contém a credencial, derivado dela, nem corpo de erro")
    func thePersistedFileCarriesNoCredential() async throws {
        let temporary = TemporaryStore()
        let harness = ProviderHarness(
            responses: [CannedResponse.reading(), Relaunch.rejection(carrying: Relaunch.errorBodyCanary)],
            store: temporary.store
        )
        #expect(await harness.waitForReading(sequence: 1))

        harness.clock.advance(by: 180)
        #expect(await harness.waitForState { $0.lastAttempt == .failed(.credentialRejected) })

        let data = try #require(temporary.contents)
        let text = try #require(String(data: data, encoding: .utf8))
        let token = StubCredentials.pasted
        let digest = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()

        #expect(!text.contains(token))
        #expect(!text.contains("oat01"))
        #expect(!text.contains(Data(token.utf8).base64EncodedString()))
        #expect(!text.contains(digest))
        #expect(!text.contains(Relaunch.errorBodyCanary))
        #expect(!text.lowercased().contains("token"))
        #expect(!text.lowercased().contains("authorization"))
    }
}
