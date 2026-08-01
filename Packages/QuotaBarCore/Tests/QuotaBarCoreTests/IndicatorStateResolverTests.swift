import Foundation
import Testing

@testable import QuotaBarCore

private enum TestState {
    static func make(
        credentialPresent: Bool = true,
        snapshot: QuotaSnapshot? = nil,
        lastAttempt: AttemptOutcome = .inProgress,
        maxIdleCadenceSinceReading: Duration = .seconds(180),
        source: QuotaSource = .primaryProbe
    ) -> QuotaState {
        QuotaState(
            credentialPresent: credentialPresent,
            snapshot: snapshot,
            lastAttempt: lastAttempt,
            cycle: TestCycle.scheduled(.seconds(180), nature: .base),
            maxIdleCadenceSinceReading: maxIdleCadenceSinceReading,
            source: source
        )
    }
}

@Suite("Resolvedor de estado do indicador")
struct IndicatorStateResolverTests {
    private static let readAt = TestSnapshot.readAt
    private static let succeeded = AttemptOutcome.succeeded(at: TestSnapshot.readAt)

    private static func resolve(
        _ state: QuotaState,
        afterSeconds seconds: TimeInterval = 60,
        latch: inout StaleLatch
    ) -> IndicatorState {
        IndicatorStateResolver.resolve(
            state: state,
            latch: &latch,
            now: readAt.addingTimeInterval(seconds)
        )
    }

    private static func resolve(_ state: QuotaState, afterSeconds seconds: TimeInterval = 60) -> IndicatorState {
        var latch = StaleLatch()
        return resolve(state, afterSeconds: seconds, latch: &latch)
    }

    @Test("sem credencial, valor de fonte primária não sustenta o indicador")
    func missingCredentialWinsOverPrimarySourceValue() {
        let state = TestState.make(
            credentialPresent: false,
            snapshot: TestSnapshot.make(fiveHourPercent: "60", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: Self.succeeded,
            source: .primaryProbe
        )

        #expect(Self.resolve(state) == .notConfigured)
    }

    @Test("sem credencial, valor de contingência é preservado")
    func contingencyValueSurvivesCredentialRemoval() {
        let snapshot = TestSnapshot.make(
            fiveHourPercent: "33",
            sevenDayPercent: nil,
            bindingWindow: nil,
            source: .contingencyStatusLine
        )
        let state = TestState.make(
            credentialPresent: false,
            snapshot: snapshot,
            lastAttempt: Self.succeeded,
            source: .contingencyStatusLine
        )

        guard case let .ready(value) = Self.resolve(state) else {
            Issue.record("esperado ready, veio \(Self.resolve(state))")
            return
        }

        #expect(value.selection.window == .fiveHour)
        #expect(value.utilization.truncatedPercent == 33)
    }

    @Test("primeiro uso, sem credencial e sem leitura")
    func firstRunWithoutCredential() {
        let state = TestState.make(credentialPresent: false, snapshot: nil, lastAttempt: .inProgress)

        #expect(Self.resolve(state) == .notConfigured)
    }

    @Test("primeira leitura em andamento")
    func firstReadingInProgress() {
        let state = TestState.make(credentialPresent: true, snapshot: nil, lastAttempt: .inProgress)

        #expect(Self.resolve(state) == .loading)
    }

    @Test(
        "falha sem valor exibível carrega o motivo, distinto para cada condição",
        arguments: FailureReason.allCases
    )
    func failureWithoutDisplayableValueCarriesReason(reason: FailureReason) {
        let state = TestState.make(credentialPresent: true, snapshot: nil, lastAttempt: .failed(reason))

        #expect(Self.resolve(state) == .failed(reason))
    }

    @Test("falha com valor exibível e idade acima do limite resulta em obsoleto, não em falha")
    func failureWithDisplayableValueBecomesStale() {
        let state = TestState.make(
            snapshot: TestSnapshot.make(fiveHourPercent: "42", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: .failed(.communicationFailure),
            maxIdleCadenceSinceReading: .seconds(180)
        )

        guard case let .stale(value) = Self.resolve(state, afterSeconds: 11 * 60) else {
            Issue.record("esperado stale")
            return
        }

        #expect(value.utilization.truncatedPercent == 42)
    }

    @Test("falha recente com valor exibível dentro do limite não marca obsolescência")
    func recentFailureKeepsValueReady() {
        let state = TestState.make(
            snapshot: TestSnapshot.make(fiveHourPercent: "42", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: .failed(.communicationFailure)
        )

        guard case let .ready(value) = Self.resolve(state, afterSeconds: 120) else {
            Issue.record("esperado ready")
            return
        }

        #expect(value.utilization.truncatedPercent == 42)
    }

    @Test("idade acima do limite torna o dado obsoleto")
    func ageBeyondLimitBecomesStale() {
        let state = TestState.make(
            snapshot: TestSnapshot.make(fiveHourPercent: "30", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: Self.succeeded
        )

        guard case let .stale(value) = Self.resolve(state, afterSeconds: 11 * 60) else {
            Issue.record("esperado stale")
            return
        }

        #expect(value.selection.window == .fiveHour)
        #expect(value.utilization.truncatedPercent == 30)
    }

    @Test("dentro do limite o dado permanece pronto")
    func ageWithinLimitStaysReady() {
        let state = TestState.make(
            snapshot: TestSnapshot.make(fiveHourPercent: "30", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: Self.succeeded
        )

        #expect(Self.resolve(state, afterSeconds: 9 * 60).isReady)
    }

    @Test("com ociosidade no teto, doze minutos de idade continuam prontos")
    func idleCeilingKeepsTwelveMinuteReadingReady() {
        let state = TestState.make(
            snapshot: TestSnapshot.make(fiveHourPercent: "30", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: Self.succeeded,
            maxIdleCadenceSinceReading: .seconds(900)
        )

        #expect(Self.resolve(state, afterSeconds: 12 * 60).isReady)
    }

    @Test("reset da janela exibida ultrapassado torna o dado obsoleto")
    func passedResetBecomesStale() {
        let snapshot = TestSnapshot.make(
            fiveHourPercent: "30",
            sevenDayPercent: nil,
            bindingWindow: .window(.fiveHour),
            fiveHourResetsAt: Self.readAt.addingTimeInterval(60)
        )
        let state = TestState.make(snapshot: snapshot, lastAttempt: Self.succeeded)

        guard case let .stale(value) = Self.resolve(state, afterSeconds: 120) else {
            Issue.record("esperado stale")
            return
        }

        #expect(value.utilization.truncatedPercent == 30)
    }

    @Test("consumo de 100% leva a esgotado")
    func oneHundredPercentBecomesExhausted() {
        let state = TestState.make(
            snapshot: TestSnapshot.make(fiveHourPercent: "100", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: Self.succeeded
        )

        guard case let .exhausted(value) = Self.resolve(state) else {
            Issue.record("esperado exhausted")
            return
        }

        #expect(value.band == .exhausted)
        #expect(value.utilization.truncatedPercent == 100)
    }

    @Test("consumo acima de 100% é esgotado, não resposta inesperada")
    func overageBecomesExhausted() {
        let state = TestState.make(
            snapshot: TestSnapshot.make(fiveHourPercent: "118", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: Self.succeeded
        )

        guard case let .exhausted(value) = Self.resolve(state) else {
            Issue.record("esperado exhausted")
            return
        }

        #expect(value.utilization.basisPoints == 11_800)
    }

    @Test("cota esgotada reportada com os percentuais é leitura, não falha")
    func reportedExhaustionIsAReading() throws {
        let snapshot = try #require(QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: TestSnapshot.utilization("100"),
                resetsAt: Self.readAt.addingTimeInterval(3_600),
                status: .rejected
            ),
            sevenDay: WindowReading(utilization: TestSnapshot.utilization("64"), resetsAt: nil, status: .allowed),
            overallStatus: .rejected,
            nextResetAt: Self.readAt.addingTimeInterval(3_600),
            bindingWindow: .window(.fiveHour),
            fallbackPercentage: nil,
            overage: OverageInfo(status: "exhausted", disabledReason: nil),
            readSequence: 1,
            readAt: Self.readAt,
            source: .primaryProbe
        ))
        let state = TestState.make(snapshot: snapshot, lastAttempt: Self.succeeded)

        let resolved = Self.resolve(state)

        #expect(resolved == .exhausted(
            DisplayValue(
                selection: .reportedByOrigin(.fiveHour),
                utilization: TestSnapshot.utilization("100")!,
                band: .exhausted
            )
        ))
    }

    @Test("obsoleto e esgotado ao mesmo tempo resolve como obsoleto")
    func stalenessTakesPrecedenceOverExhaustion() {
        let state = TestState.make(
            snapshot: TestSnapshot.make(fiveHourPercent: "100", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: Self.succeeded
        )

        guard case let .stale(value) = Self.resolve(state, afterSeconds: 11 * 60) else {
            Issue.record("esperado stale")
            return
        }

        #expect(value.band == .exhausted)
    }

    @Test("a faixa é calculada sobre a janela exibida")
    func bandFollowsDisplayedWindow() {
        let state = TestState.make(
            snapshot: TestSnapshot.make(fiveHourPercent: "20", sevenDayPercent: "92", bindingWindow: .window(.sevenDay)),
            lastAttempt: Self.succeeded
        )

        guard case let .ready(value) = Self.resolve(state) else {
            Issue.record("esperado ready")
            return
        }

        #expect(value.selection.window == .sevenDay)
        #expect(value.utilization.truncatedPercent == 92)
        #expect(value.band == .critical)
    }

    @Test("leitura no futuro é tratada como idade zero")
    func readingInTheFutureIsTreatedAsAgeZero() {
        let state = TestState.make(
            snapshot: TestSnapshot.make(fiveHourPercent: "30", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: Self.succeeded
        )

        #expect(Self.resolve(state, afterSeconds: -3_600).isReady)
    }

    @Test("a trava atravessa chamadas do resolvedor")
    func latchSurvivesAcrossResolutions() {
        let state = TestState.make(
            snapshot: TestSnapshot.make(fiveHourPercent: "30", sevenDayPercent: nil, bindingWindow: .window(.fiveHour)),
            lastAttempt: Self.succeeded
        )
        var latch = StaleLatch()

        let afterLimit = Self.resolve(state, afterSeconds: 11 * 60, latch: &latch)
        let backWithinLimit = Self.resolve(state, afterSeconds: 120, latch: &latch)

        #expect(afterLimit.isStale)
        #expect(backWithinLimit.isStale)
    }

    @Test("leitura sem nenhum percentual é recusada na construção, não exibida com zeros")
    func readingWithoutAnyUtilizationIsRefusedAtConstruction() {
        #expect(TestSnapshot.build(fiveHourPercent: nil, sevenDayPercent: nil, bindingWindow: nil) == nil)
        #expect(TestSnapshot.build(fiveHourPercent: nil, sevenDayPercent: nil, bindingWindow: .window(.fiveHour)) == nil)
    }

    @Test("leitura válida exige ao menos uma janela com percentual")
    func aValidReadingNeedsAtLeastOneWindow() {
        #expect(TestSnapshot.build(fiveHourPercent: "0", sevenDayPercent: nil, bindingWindow: nil) != nil)
        #expect(TestSnapshot.build(fiveHourPercent: nil, sevenDayPercent: "0", bindingWindow: nil) != nil)
    }
}

private extension IndicatorState {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
