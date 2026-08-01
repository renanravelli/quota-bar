import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Tipos de leitura e de estado — invariantes")
struct QuotaStateTypesTests {
    private static func reading(percent: String) -> WindowReading {
        WindowReading(
            utilization: Utilization(originPercent: Decimal(string: percent)!),
            resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: .allowed
        )
    }

    @Test("AC-48: só a fonte primária exige credencial")
    func onlyPrimarySourceRequiresCredential() {
        #expect(QuotaSource.primaryProbe.requiresCredential)
        #expect(!QuotaSource.contingencyStatusLine.requiresCredential)
    }

    @Test("AC-37: cadência abaixo do piso de 60 segundos não é construível")
    func cadenceRefusesIntervalBelowFloor() {
        #expect(Cadence(interval: .seconds(59), nature: .base) == nil)
        #expect(Cadence(interval: .seconds(1), nature: .idle) == nil)
        #expect(Cadence(interval: .zero, nature: .base) == nil)
        #expect(Cadence(interval: .seconds(-60), nature: .base) == nil)
    }

    @Test("AC-37: o piso de 60 segundos é aceito, e a ociosidade no teto também")
    func cadenceAcceptsFloorAndIdleCeiling() {
        #expect(Cadence(interval: .seconds(60), nature: .base)?.interval == .seconds(60))
        #expect(Cadence(interval: .seconds(900), nature: .idle)?.nature == .idle)
        #expect(Cadence(interval: .seconds(1_800), nature: .widenedByFailure) != nil)
        #expect(Cadence.floor == .seconds(60))
    }

    @Test("AC-32: status desconhecido preserva o valor original em vez de derrubar a leitura")
    func unknownStatusKeepsOriginalValue() {
        let status = WindowStatus.unknown("allowed_with_grace")

        #expect(status == .unknown("allowed_with_grace"))
        #expect(status != .unknown("rejected"))
        #expect(status != .allowed)
    }

    @Test("AC-31: janela limitante ausente permanece ausente, mesmo com as duas janelas disponíveis")
    func absentBindingWindowIsNotDerived() throws {
        let snapshot = try #require(QuotaSnapshot(
            fiveHour: Self.reading(percent: "31"),
            sevenDay: Self.reading(percent: "67"),
            overallStatus: .allowed,
            nextResetAt: nil,
            bindingWindow: nil,
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: 1,
            readAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .primaryProbe
        ))

        #expect(snapshot.bindingWindow == nil)
        #expect(snapshot.fiveHour.utilization != nil)
        #expect(snapshot.sevenDay.utilization != nil)
    }

    @Test("AC-7: estado sem credencial, sem leitura e sem tentativa concluída ainda carrega uma tentativa")
    func attemptOutcomeIsNeverAbsent() {
        let state = QuotaState(
            credentialPresent: false,
            snapshot: nil,
            cycle: TestCycle.scheduled(.seconds(180), nature: .base),
            maxIdleCadenceSinceReading: .seconds(180),
            source: .primaryProbe
        )

        #expect(state.lastAttempt == .inProgress)
        #expect(state.snapshot == nil)
        #expect(state.unavailableFields.isEmpty)
    }

    @Test("AC-42: campo não fornecido é declarado ausente, não preenchido")
    func unavailableFieldsRecordAbsenceInsteadOfDefaults() throws {
        let sevenDay = WindowReading(utilization: Utilization(basisPoints: 4_100), resetsAt: nil, status: .allowed)
        let snapshot = try #require(QuotaSnapshot(
            fiveHour: Self.reading(percent: "78"),
            sevenDay: sevenDay,
            overallStatus: .allowed,
            nextResetAt: nil,
            bindingWindow: .window(.fiveHour),
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: 1,
            readAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .contingencyStatusLine
        ))
        let state = QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .succeeded(at: Date(timeIntervalSince1970: 1_700_000_000)),
            cycle: TestCycle.scheduled(.seconds(900), nature: .idle),
            maxIdleCadenceSinceReading: .seconds(900),
            source: .contingencyStatusLine,
            unavailableFields: [.resetAt(.sevenDay), .bindingWindow]
        )

        #expect(snapshot.sevenDay.resetsAt == nil)
        #expect(state.unavailableFields.contains(.resetAt(.sevenDay)))
        #expect(state.unavailableFields.contains(.bindingWindow))
        #expect(!state.unavailableFields.contains(.resetAt(.fiveHour)))
    }

    @Test("AC-9: tentativa bem-sucedida sem leitura é incoerência recusada na construção")
    func succeededWithoutSnapshotIsNotConstructible() async {
        await #expect(processExitsWith: .failure) {
            _ = QuotaState(
                credentialPresent: true,
                snapshot: nil,
                lastAttempt: .succeeded(at: Date(timeIntervalSince1970: 1_700_000_000)),
                cycle: TestCycle.scheduled(.seconds(180), nature: .base),
                maxIdleCadenceSinceReading: .seconds(180),
                source: .primaryProbe
            )
        }
    }

    @Test("AC-8: tentativa em andamento sem leitura continua construível")
    func inProgressWithoutSnapshotStaysConstructible() {
        let state = QuotaState(
            credentialPresent: true,
            snapshot: nil,
            lastAttempt: .inProgress,
            cycle: TestCycle.scheduled(.seconds(180), nature: .base),
            maxIdleCadenceSinceReading: .seconds(180),
            source: .primaryProbe
        )

        #expect(state.snapshot == nil)
    }

    @Test("AC-9 e AC-49: os sete motivos de falha são distintos entre si")
    func failureReasonsAreDistinct() {
        #expect(Set(FailureReason.allCases).count == 7)
        #expect(FailureReason.allCases.contains(.claudeCodeNotFound))
    }

    private static func awaiting(credential: Bool, claudeCode: Bool) -> QuotaState {
        QuotaState(
            credentialPresent: !credential,
            claudeCodeMissing: claudeCode,
            snapshot: nil,
            lastAttempt: .inProgress,
            cycle: nil,
            maxIdleCadenceSinceReading: ScheduledCadence.floor,
            source: nil
        )
    }

    @Test("AC-51: as duas pendências coexistem, sem que uma dependa da outra")
    func bothPendenciesCoexist() {
        #expect(Self.awaiting(credential: true, claudeCode: true).pendencies == [.credential, .claudeCode])
    }

    @Test("AC-49 e AC-51: cada pendência é declarada sozinha quando é a única")
    func eachPendencyStandsAlone() {
        #expect(Self.awaiting(credential: false, claudeCode: true).pendencies == [.claudeCode])
        #expect(Self.awaiting(credential: true, claudeCode: false).pendencies == [.credential])
    }

    @Test("REQ-19: sem pendência alguma, nenhuma é declarada")
    func noPendencyIsInvented() {
        #expect(Self.awaiting(credential: false, claudeCode: false).pendencies.isEmpty)
        #expect(ConfigurationPendency.allCases.count == 2)
    }

    @Test("AC-7: o estado inicial do aplicativo é o de credencial não configurada, sem afirmar cadência nem fonte")
    func theInitialStateAffirmsNothingItDoesNotKnow() {
        var latch = StaleLatch()
        let state = QuotaState.unconfigured

        #expect(IndicatorStateResolver.resolve(state: state, latch: &latch, now: Date()) == .notConfigured)
        #expect(state.pendencies == [.credential])
        #expect(state.snapshot == nil)
        #expect(state.cycle == nil)
        #expect(state.source == nil)
    }
}
