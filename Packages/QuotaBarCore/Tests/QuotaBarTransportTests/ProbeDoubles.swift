import Foundation
import QuotaBarCore
import QuotaBarCoreFixtures
import os

@testable import QuotaBarTransport

enum CannedResponse {
    static let readingHeaders = UnifiedRateLimitHeaderFixture.complete.headers

    static func reading(_ fixture: UnifiedRateLimitHeaderFixture = .complete, status: Int = 200) -> ProbeHTTPResponse {
        ProbeHTTPResponse(status: status, headers: fixture.headers, body: Data("{\"id\":\"msg_1\"}".utf8))
    }

    static func throttled(retryAfterSeconds: Int? = nil) -> ProbeHTTPResponse {
        ProbeHTTPResponse(
            status: 429,
            headers: retryAfterSeconds.map { ProbeResponseFixture.Headers.retryAfter(seconds: $0) } ?? [:],
            body: Data()
        )
    }

    static func serverError() -> ProbeHTTPResponse {
        ProbeHTTPResponse(status: 503, headers: [:], body: Data())
    }

    static func rejected(_ body: Data = ProbeResponseFixture.ErrorBody.unrecognized) -> ProbeHTTPResponse {
        ProbeHTTPResponse(status: 401, headers: [:], body: body)
    }

    static func unknownModel() -> ProbeHTTPResponse {
        ProbeHTTPResponse(
            status: 404,
            headers: [:],
            body: Data(#"{"type":"error","error":{"type":"not_found_error","message":"model: unknown model"}}"#.utf8)
        )
    }
}

final class RecordingTransport: ProbeTransporting, Sendable {
    private struct Ledger {
        var queued: [ProbeHTTPResponse] = []
        var repeating: ProbeHTTPResponse?
        var failing = false
        var sent: [ProbeRequest] = []
    }

    private let ledger = OSAllocatedUnfairLock(initialState: Ledger())

    init(_ responses: [ProbeHTTPResponse] = [], failing: Bool = false) {
        ledger.withLock {
            $0.queued = responses
            $0.repeating = responses.last
            $0.failing = failing
        }
    }

    var sent: [ProbeRequest] {
        ledger.withLock { $0.sent }
    }

    var sentCount: Int {
        ledger.withLock { $0.sent.count }
    }

    func send(_ request: ProbeRequest) async throws -> ProbeHTTPResponse {
        try ledger.withLock { ledger in
            ledger.sent.append(request)
            if ledger.failing { throw URLError(.notConnectedToInternet) }
            guard !ledger.queued.isEmpty else {
                guard let repeating = ledger.repeating else { throw URLError(.badServerResponse) }
                return repeating
            }
            return ledger.queued.removeFirst()
        }
    }
}

struct StubCredentials: CredentialStoring {
    let outcome: KeychainOutcome<SubscriptionToken>

    static let pasted = "sk-ant-oat01-test-value-0123456789"

    static var configured: StubCredentials {
        StubCredentials(outcome: .success(SubscriptionToken(pasted: pasted)!))
    }

    static func failing(_ failure: KeychainFailure) -> StubCredentials {
        StubCredentials(outcome: .failure(failure))
    }

    func store(_ token: SubscriptionToken) async -> KeychainOutcome<Void> { .success(()) }

    func load() async -> KeychainOutcome<SubscriptionToken> { outcome }

    func remove() async -> KeychainOutcome<Void> { .success(()) }

    func isConfigured() async -> KeychainOutcome<Bool> {
        switch outcome {
        case .success: .success(true)
        case .failure(let failure): failure == .itemNotFound ? .success(false) : .failure(failure)
        }
    }
}

final class SwitchableCredentials: CredentialStoring, Sendable {
    private let token: OSAllocatedUnfairLock<SubscriptionToken?>

    init(configured: Bool = false) {
        token = OSAllocatedUnfairLock(
            initialState: configured ? SubscriptionToken(pasted: StubCredentials.pasted) : nil
        )
    }

    func store(_ token: SubscriptionToken) async -> KeychainOutcome<Void> {
        self.token.withLock { $0 = token }
        return .success(())
    }

    func load() async -> KeychainOutcome<SubscriptionToken> {
        token.withLock { stored in stored.map { .success($0) } ?? .failure(.itemNotFound) }
    }

    func remove() async -> KeychainOutcome<Void> {
        token.withLock { $0 = nil }
        return .success(())
    }

    func isConfigured() async -> KeychainOutcome<Bool> {
        .success(token.withLock { $0 != nil })
    }
}

final class GatedCredentials: CredentialStoring, Sendable {
    private struct Gate {
        var calls = 0
        var open = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let backing = StubCredentials.configured
    private let gate = OSAllocatedUnfairLock(initialState: Gate())
    private let blockedCall: Int

    init(blockingCall: Int) {
        blockedCall = blockingCall
    }

    var parked: Bool {
        gate.withLock { !$0.waiting.isEmpty }
    }

    func open() {
        let released = gate.withLock { gate in
            gate.open = true
            defer { gate.waiting = [] }
            return gate.waiting
        }
        for continuation in released { continuation.resume() }
    }

    func store(_ token: SubscriptionToken) async -> KeychainOutcome<Void> { await backing.store(token) }

    func load() async -> KeychainOutcome<SubscriptionToken> { await backing.load() }

    func remove() async -> KeychainOutcome<Void> { await backing.remove() }

    func isConfigured() async -> KeychainOutcome<Bool> {
        await passGate()
        return await backing.isConfigured()
    }

    private func passGate() async {
        await withCheckedContinuation { continuation in
            let proceeds = gate.withLock { gate in
                gate.calls += 1
                guard gate.calls >= blockedCall, !gate.open else { return true }
                gate.waiting.append(continuation)
                return false
            }
            if proceeds { continuation.resume() }
        }
    }
}

final class ControlledClock: DateProviding, DeadlineWaiting, Sendable {
    private let instant: OSAllocatedUnfairLock<Date>

    init(at instant: Date) {
        self.instant = OSAllocatedUnfairLock(initialState: instant)
    }

    var now: Date {
        instant.withLock { $0 }
    }

    func advance(by seconds: TimeInterval) {
        instant.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    func wait(until deadline: Date) async {
        while !Task.isCancelled, now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

final class SilentPowerEvents: SystemPowerEventObserving, Sendable {
    let powerEvents: AsyncStream<SystemPowerEvent>

    private let continuation: AsyncStream<SystemPowerEvent>.Continuation

    init() {
        (powerEvents, continuation) = AsyncStream.makeStream(of: SystemPowerEvent.self)
    }

    func send(_ event: SystemPowerEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }
}

struct InertActivity: SystemActivityAsserting {
    func beginProbeActivity() -> SystemActivityAssertion {
        SystemActivityAssertion {}
    }
}

final class CountingClaudeCode: ClaudeCodeEnvironment, Sendable {
    private let queries = OSAllocatedUnfairLock(initialState: 0)

    var versionQueries: Int {
        queries.withLock { $0 }
    }

    func executables(at candidate: ClaudeCodeCandidatePath) -> [ClaudeCodeExecutable] {
        guard candidate == ClaudeCodeCandidatePath.ordered.first else { return [] }
        return [ClaudeCodeExecutable(path: "/stub/claude", modifiedAt: Date(timeIntervalSince1970: 1), size: 1)]
    }

    func versionOutput(of executable: ClaudeCodeExecutable) -> String? {
        queries.withLock { $0 += 1 }
        return "2.1.220 (Claude Code)"
    }
}

final class StubClaudeCode: ClaudeCodeEnvironment, Sendable {
    private let reported: OSAllocatedUnfairLock<String?>

    init(version: String? = "2.1.220 (Claude Code)") {
        reported = OSAllocatedUnfairLock(initialState: version)
    }

    func uninstall() {
        reported.withLock { $0 = nil }
    }

    func install(version: String) {
        reported.withLock { $0 = version }
    }

    func executables(at candidate: ClaudeCodeCandidatePath) -> [ClaudeCodeExecutable] {
        guard reported.withLock({ $0 }) != nil, candidate == ClaudeCodeCandidatePath.ordered.first else { return [] }
        return [ClaudeCodeExecutable(path: "/stub/claude", modifiedAt: Date(timeIntervalSince1970: 1), size: 1)]
    }

    func versionOutput(of executable: ClaudeCodeExecutable) -> String? {
        reported.withLock { $0 }
    }
}
