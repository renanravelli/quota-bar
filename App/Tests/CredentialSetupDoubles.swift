import Foundation
import QuotaBarCore
import QuotaBarTransport

@testable import QuotaBar

let credentialCanary = "sk-ant-oat01-CANARIO-QUE-NAO-PODE-APARECER-EM-LUGAR-NENHUM"

actor RecordingCredentialStore: CredentialStoring {
    private(set) var storeCount = 0
    private(set) var loadCount = 0
    private(set) var removeCount = 0

    private var value: String?
    private var writeFailure: KeychainFailure?
    private var removeFailure: KeychainFailure?
    private var presenceFailure: KeychainFailure?

    init(seeded: String? = nil) {
        value = seeded
    }

    func refuseWrites(with failure: KeychainFailure) {
        writeFailure = failure
    }

    func refuseRemoval(with failure: KeychainFailure) {
        removeFailure = failure
    }

    func refusePresenceCheck(with failure: KeychainFailure) {
        presenceFailure = failure
    }

    func holds(_ expected: String) -> Bool {
        value == expected
    }

    var isPopulated: Bool {
        value != nil
    }

    func store(_ token: SubscriptionToken) async -> KeychainOutcome<Void> {
        storeCount += 1
        if let writeFailure { return .failure(writeFailure) }
        value = token.withValue { $0 }
        return .success(())
    }

    func load() async -> KeychainOutcome<SubscriptionToken> {
        loadCount += 1
        guard let value, let token = SubscriptionToken(pasted: value) else { return .failure(.itemNotFound) }
        return .success(token)
    }

    func remove() async -> KeychainOutcome<Void> {
        removeCount += 1
        if let removeFailure { return .failure(removeFailure) }
        value = nil
        return .success(())
    }

    func isConfigured() async -> KeychainOutcome<Bool> {
        if let presenceFailure { return .failure(presenceFailure) }
        return .success(value != nil)
    }
}

actor GatedVerifier: CredentialVerifying {
    private(set) var calls = 0

    private var outcome: VerificationOutcome
    private var isOpen: Bool
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ outcome: VerificationOutcome, gated: Bool = false) {
        self.outcome = outcome
        isOpen = !gated
    }

    func answer(_ next: VerificationOutcome) {
        outcome = next
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting.removeAll()
    }

    func verify(_ token: SubscriptionToken) async -> VerificationOutcome {
        calls += 1
        if !isOpen {
            await withCheckedContinuation { waiting.append($0) }
        }
        return outcome
    }
}

actor DiscoverySwitch {
    private var current: ClaudeCodeDiscovery

    init(_ current: ClaudeCodeDiscovery) {
        self.current = current
    }

    func set(_ next: ClaudeCodeDiscovery) {
        current = next
    }

    func read() -> ClaudeCodeDiscovery {
        current
    }
}

actor CredentialChangeSpy {
    private(set) var notifications = 0

    func record() {
        notifications += 1
    }

    nonisolated var notify: @Sendable () async -> Void {
        { await self.record() }
    }
}

final class StubProbeTransport: ProbeTransporting, @unchecked Sendable {
    private(set) var sent: [ProbeRequest] = []

    private let response: ProbeHTTPResponse

    init(_ response: ProbeHTTPResponse) {
        self.response = response
    }

    func send(_ request: ProbeRequest) async throws -> ProbeHTTPResponse {
        sent.append(request)
        return response
    }
}

struct StubClaudeCodeEnvironment: ClaudeCodeEnvironment {
    let version: String?

    func executables(at candidate: ClaudeCodeCandidatePath) -> [ClaudeCodeExecutable] {
        guard version != nil, candidate == ClaudeCodeCandidatePath.ordered.first else { return [] }
        return [ClaudeCodeExecutable(path: "/stub/claude", modifiedAt: .distantPast, size: 1)]
    }

    func versionOutput(of executable: ClaudeCodeExecutable) -> String? {
        version
    }
}

final class SpyClipboard: CommandCopying {
    private(set) var copied: [String] = []

    func copy(_ command: String) {
        copied.append(command)
    }
}

struct UnavailablePseudoTerminal: PseudoTerminalSpawning {
    func spawn(_ command: TerminalCommand) throws -> any PseudoTerminalSession {
        throw PseudoTerminalFailure.cannotLaunch
    }
}

actor StubAssistedAcquirer: AssistedCredentialAcquiring {
    enum Script: Sendable {
        case obtains(String)
        case unavailable(AssistedSetupUnavailability)
    }

    private(set) var acquisitions = 0
    private(set) var submittedCodes: [String] = []

    private var script: Script
    private var submissionResponse: CodeSubmission
    private let reachesApproval: Bool
    private let isGated: Bool
    private var waiting: CheckedContinuation<Void, Never>?
    private var isReleased = false

    init(
        _ script: Script = .obtains(credentialCanary),
        reachesApproval: Bool = true,
        gated: Bool = false,
        answersSubmissionWith submissionResponse: CodeSubmission = .delivered
    ) {
        self.script = script
        self.reachesApproval = reachesApproval
        self.isGated = gated
        self.submissionResponse = submissionResponse
    }

    func rewrite(_ next: Script) {
        script = next
    }

    func release() {
        isReleased = true
        waiting?.resume()
        waiting = nil
    }

    func acquire(
        onProgress: @escaping @Sendable (AssistedSetupProgress) -> Void
    ) async -> AssistedSetupOutcome {
        acquisitions += 1
        onProgress(.launching)
        if reachesApproval { onProgress(.waitingForApproval) }

        if isGated, !isReleased {
            await withTaskCancellationHandler {
                await withCheckedContinuation { waiting = $0 }
            } onCancel: {
                Task { await self.release() }
            }
        }

        if Task.isCancelled { return .cancelled }

        switch script {
        case .obtains(let value):
            guard let token = SubscriptionToken(pasted: value) else {
                return .unavailable(.endedWithoutCredential)
            }
            return .obtained(token)
        case .unavailable(let cause):
            return .unavailable(cause)
        }
    }

    func submit(code: String) async -> CodeSubmission {
        if submissionResponse == .delivered { submittedCodes.append(code) }
        return submissionResponse
    }
}

@MainActor
enum Setup {
    static let installed = ClaudeCodeDiscovery.installed(
        ClaudeCodeInstallation(
            version: "2.1.220",
            executable: ClaudeCodeExecutable(path: "/opt/homebrew/bin/claude", modifiedAt: .distantPast, size: 1)
        )
    )

    static func model(
        store: RecordingCredentialStore = RecordingCredentialStore(),
        verifier: GatedVerifier = GatedVerifier(.success),
        acquirer: StubAssistedAcquirer = StubAssistedAcquirer(),
        discovery: ClaudeCodeDiscovery = Setup.installed,
        clipboard: SpyClipboard = SpyClipboard(),
        credentialDidChange: CredentialChangeSpy = CredentialChangeSpy()
    ) -> CredentialSetupModel {
        CredentialSetupModel(
            store: store,
            verifier: verifier,
            acquirer: acquirer,
            claudeCode: { discovery },
            credentialDidChange: credentialDidChange.notify,
            clipboard: clipboard
        )
    }

    static func opened(
        store: RecordingCredentialStore = RecordingCredentialStore(),
        verifier: GatedVerifier = GatedVerifier(.success),
        acquirer: StubAssistedAcquirer = StubAssistedAcquirer(),
        discovery: ClaudeCodeDiscovery = Setup.installed,
        clipboard: SpyClipboard = SpyClipboard(),
        credentialDidChange: CredentialChangeSpy = CredentialChangeSpy()
    ) async -> CredentialSetupModel {
        let model = model(
            store: store,
            verifier: verifier,
            acquirer: acquirer,
            discovery: discovery,
            clipboard: clipboard,
            credentialDidChange: credentialDidChange
        )
        await model.refresh()
        return model
    }

    static func settle(_ model: CredentialSetupModel, until reached: CredentialSetupStage) async {
        for _ in 0..<10_000 where model.stage != reached {
            await Task.yield()
        }
    }

    static func settle(untilTrue reached: @MainActor () -> Bool) async {
        for _ in 0..<10_000 where !reached() {
            await Task.yield()
        }
    }

    static func settle(_ acquirer: StubAssistedAcquirer, untilAcquisitions count: Int) async {
        for _ in 0..<10_000 where await acquirer.acquisitions < count {
            await Task.yield()
        }
    }

    static func settle(_ verifier: GatedVerifier, untilCalled calls: Int) async {
        for _ in 0..<10_000 where await verifier.calls < calls {
            await Task.yield()
        }
    }

    static func text(of content: CredentialSetupContent) -> [String] {
        var strings = [content.title, content.command, content.copyCommandTitle, content.fieldLabel, content.saveTitle]
        strings.append(content.commandStep)
        strings.append(contentsOf: content.steps)
        strings.append(contentsOf: [
            content.cancelTitle, content.replaceTitle, content.removeTitle,
            content.precondition, content.configuredNotice, content.message?.text,
            content.assistTitle, content.assistUnavailableReason, content.codeFieldLabel,
            content.saveAvailability.reason, content.costNotice, content.waitingNotice
        ].compactMap { $0 })
        return strings
    }
}
