import Foundation
import Testing

import QuotaBarCoreFixtures
@testable import QuotaBarCore

@Suite("QB-API-001 — classificação da resposta")
struct ResponseClassifierTests {
    private static let readSequence: UInt64 = 7
    private static let readAt = Date(timeIntervalSince1970: 1_700_000_000)
    private static let canary = "QUOTABAR-CANARIO-4f2a9c"

    private static let withoutUtilizations = UnifiedRateLimitHeaderFixture(
        fiveHourReset: "1700003600",
        fiveHourStatus: "allowed",
        sevenDayReset: "1700086400",
        sevenDayStatus: "allowed",
        overallStatus: "allowed"
    ).headers

    private static let fiveHourOnly = UnifiedRateLimitHeaderFixture(
        fiveHourUtilization: "0.42",
        fiveHourReset: "1700003600",
        fiveHourStatus: "allowed",
        overallStatus: "allowed"
    ).headers

    private static func classify(
        status: Int,
        headers: [String: String] = [:],
        errorBody: Data? = nil
    ) -> ProbeResult {
        ResponseClassifier.classify(
            status: status,
            headers: headers,
            errorBody: errorBody,
            readSequence: readSequence,
            readAt: readAt
        )
    }

    private static func snapshot(in result: ProbeResult) -> QuotaSnapshot? {
        guard case .reading(let snapshot) = result else { return nil }
        return snapshot
    }

    private static func failureReason(in result: ProbeResult) -> FailureReason? {
        guard case .failed(let reason) = result else { return nil }
        return reason
    }

    @Test("AC-21: 429 com cabeçalhos unified é leitura bem-sucedida, não estrangulamento")
    func exhaustedQuotaWithHeadersIsAReading() throws {
        let result = Self.classify(status: 429, headers: UnifiedRateLimitHeaderFixture.exhausted.headers)

        let snapshot = try #require(Self.snapshot(in: result))
        #expect(snapshot.fiveHour.utilization?.isAtOrAboveLimit == true)
        #expect(snapshot.fiveHour.status == .rejected)
        #expect(snapshot.sevenDay.utilization != nil)
    }

    @Test("AC-21: resposta bem-sucedida com cabeçalhos unified é leitura, com a identidade recebida")
    func successWithHeadersIsAReading() throws {
        let result = Self.classify(status: 200, headers: UnifiedRateLimitHeaderFixture.complete.headers)

        let snapshot = try #require(Self.snapshot(in: result))
        #expect(snapshot.fiveHour.utilization?.truncatedPercent == 78)
        #expect(snapshot.sevenDay.utilization?.truncatedPercent == 18)
        #expect(snapshot.bindingWindow == .window(.fiveHour))
        #expect(snapshot.readSequence == Self.readSequence)
        #expect(snapshot.readAt == Self.readAt)
    }

    @Test("AC-21: uma única janela presente ainda é leitura")
    func singleWindowIsStillAReading() throws {
        let result = Self.classify(status: 200, headers: Self.fiveHourOnly)

        let snapshot = try #require(Self.snapshot(in: result))
        #expect(snapshot.fiveHour.utilization != nil)
        #expect(snapshot.sevenDay.utilization == nil)
    }

    @Test("AC-22: 429 sem cabeçalhos unified é estrangulamento de transporte")
    func throttlingWithoutHeadersIsNotAReading() {
        let result = Self.classify(status: 429, headers: ProbeResponseFixture.Headers.absent)

        #expect(result == .throttled(retryAfter: nil))
        #expect(Self.snapshot(in: result) == nil)
    }

    @Test("AC-22: 429 com cabeçalhos unified sem utilização é estrangulamento, não leitura de zeros")
    func throttlingWithHeadersButNoUtilizationIsNotAReading() {
        let result = Self.classify(status: 429, headers: Self.withoutUtilizations)

        #expect(result == .throttled(retryAfter: nil))
    }

    @Test("AC-22: Retry-After é lido sem depender da caixa do cabeçalho, e só em segundos")
    func retryAfterIsHonoredCaseInsensitively() {
        #expect(
            Self.classify(status: 429, headers: ProbeResponseFixture.Headers.retryAfter(seconds: 30))
                == .throttled(retryAfter: .seconds(30))
        )
        #expect(
            Self.classify(status: 429, headers: ProbeResponseFixture.Headers.retryAfterInUpperCase(seconds: 45))
                == .throttled(retryAfter: .seconds(45))
        )
        #expect(
            Self.classify(status: 429, headers: ProbeResponseFixture.Headers.retryAfterAsHTTPDate)
                == .throttled(retryAfter: nil)
        )
    }

    @Test("AC-22: falha do lado da origem é estrangulamento")
    func serverFailureIsThrottling() {
        #expect(Self.classify(status: 500) == .throttled(retryAfter: nil))
        #expect(
            Self.classify(status: 503, headers: ProbeResponseFixture.Headers.retryAfter(seconds: 120))
                == .throttled(retryAfter: .seconds(120))
        )
        #expect(Self.classify(status: 599) == .throttled(retryAfter: nil))
    }

    @Test("AC-8: as duas utilizações ausentes produzem resposta inesperada, nunca um estado com zeros")
    func bothUtilizationsAbsentIsUnexpectedResponse() {
        let withOtherHeaders = Self.classify(status: 200, headers: Self.withoutUtilizations)
        let withoutAnyHeader = Self.classify(status: 200, headers: ProbeResponseFixture.Headers.absent)

        #expect(withOtherHeaders == .failed(.unexpectedResponse))
        #expect(withoutAnyHeader == .failed(.unexpectedResponse))
        #expect(Self.snapshot(in: withOtherHeaders) == nil)
        #expect(Self.snapshot(in: withoutAnyHeader) == nil)
    }

    @Test("AC-24: bloqueio por política exige evidência positiva no corpo")
    func policyBlockRequiresPositiveEvidence() {
        let withEvidence = Self.classify(status: 403, errorBody: ProbeResponseFixture.ErrorBody.policyRestriction)
        let unrecognized = Self.classify(status: 403, errorBody: ProbeResponseFixture.ErrorBody.unrecognized)
        let empty = Self.classify(status: 403, errorBody: ProbeResponseFixture.ErrorBody.empty)
        let unexpectedShape = Self.classify(status: 403, errorBody: ProbeResponseFixture.ErrorBody.unexpectedShape)

        #expect(withEvidence == .failed(.blockedByPolicy))
        #expect(unrecognized == .failed(.credentialRejected))
        #expect(empty == .failed(.credentialRejected))
        #expect(unexpectedShape == .failed(.credentialRejected))
    }

    @Test("AC-24: corpo ausente ou ilegível é credencial recusada, em nenhuma hipótese bloqueio por política")
    func unreadableBodyNeverBecomesPolicyBlock() {
        let bodies: [Data?] = [
            nil,
            ProbeResponseFixture.ErrorBody.empty,
            ProbeResponseFixture.ErrorBody.unreadable,
            ProbeResponseFixture.ErrorBody.unexpectedShape,
            ProbeResponseFixture.ErrorBody.notJSON,
            ProbeResponseFixture.ErrorBody.unrecognized
        ]

        for status in [401, 403] {
            for body in bodies {
                let result = Self.classify(status: status, errorBody: body)

                #expect(result == .failed(.credentialRejected))
                #expect(result != .failed(.blockedByPolicy))
            }
        }
    }

    @Test("AC-25: recusa sem evidência de expiração é recusa; com evidência é expiração")
    func expirationRequiresEvidence() {
        #expect(
            Self.classify(status: 401, errorBody: ProbeResponseFixture.ErrorBody.unrecognized)
                == .failed(.credentialRejected)
        )
        #expect(
            Self.classify(status: 401, errorBody: ProbeResponseFixture.ErrorBody.expiredCredential)
                == .failed(.credentialExpired)
        )
        #expect(
            Self.classify(status: 401, errorBody: ProbeResponseFixture.ErrorBody.revokedCredential)
                == .failed(.credentialRejected)
        )
    }

    @Test("AC-23: cada resposta preparada produz exatamente um motivo, e os motivos são distinguíveis")
    func eachResponseProducesExactlyOneReason() {
        let classified: [ProbeResult] = [
            Self.classify(status: 401, errorBody: ProbeResponseFixture.ErrorBody.unrecognized),
            Self.classify(status: 401, errorBody: ProbeResponseFixture.ErrorBody.expiredCredential),
            Self.classify(status: 403, errorBody: ProbeResponseFixture.ErrorBody.policyRestriction),
            Self.classify(status: 200, headers: ProbeResponseFixture.Headers.absent)
        ]
        let reasons = classified.compactMap(Self.failureReason(in:))

        #expect(reasons.count == classified.count)
        #expect(
            Set(reasons) == [
                .credentialRejected,
                .credentialExpired,
                .blockedByPolicy,
                .unexpectedResponse
            ]
        )
    }

    @Test("AC-23: 4xx que não é 401, 403 nem 429 é resposta inesperada")
    func otherClientErrorsAreUnexpectedResponses() {
        #expect(Self.classify(status: 400) == .failed(.unexpectedResponse))
        #expect(Self.classify(status: 404) == .failed(.unexpectedResponse))
        #expect(Self.classify(status: 302) == .failed(.unexpectedResponse))
    }

    @Test("AC-27: em resposta bem-sucedida o corpo não é interpretado")
    func successNeverInspectsTheBody() throws {
        let reading = Self.classify(
            status: 200,
            headers: UnifiedRateLimitHeaderFixture.complete.headers,
            errorBody: ProbeResponseFixture.ErrorBody.policyRestriction
        )
        let withoutHeaders = Self.classify(
            status: 200,
            headers: ProbeResponseFixture.Headers.absent,
            errorBody: ProbeResponseFixture.ErrorBody.policyRestriction
        )

        #expect(try #require(Self.snapshot(in: reading)).fiveHour.utilization?.truncatedPercent == 78)
        #expect(withoutHeaders == .failed(.unexpectedResponse))
    }

    @Test("AC-26: o corpo de erro não sobrevive à classificação")
    func errorBodyDoesNotSurviveClassification() {
        let result = Self.classify(
            status: 403,
            errorBody: ProbeResponseFixture.ErrorBody.withCanary(Self.canary)
        )

        #expect(result == .failed(.credentialRejected))
        #expect(!String(describing: result).contains(Self.canary))
        #expect(!String(reflecting: result).contains(Self.canary))
    }
}
