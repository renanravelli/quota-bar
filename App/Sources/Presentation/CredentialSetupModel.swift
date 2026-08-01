import AppKit
import Foundation
import Observation
import QuotaBarCore
import QuotaBarTransport

enum CredentialSetupStage: Equatable {
    case blockedByPrecondition
    case empty
    case assisting
    case verifying
    case configured
    case configuredWithReservation
    case refused
}

struct CredentialSetupContent: Equatable {
    let stage: CredentialSetupStage
    let title: String
    let commandStep: String
    let steps: [String]
    let command: String
    let copyCommandTitle: String
    let fieldLabel: String
    let saveTitle: String
    let cancelTitle: String?
    let replaceTitle: String?
    let removeTitle: String?
    let precondition: String?
    let configuredNotice: String?
    let message: CredentialSetupMessage?
    let showsField: Bool
    let canSave: Bool
    let assistTitle: String?
    let assistUnavailableReason: String?
    let codeFieldLabel: String?
    let saveDisabledReason: String?
    let costNotice: String?
    let waitingNotice: String?
}

protocol CommandCopying {
    func copy(_ command: String)
}

struct SystemPasteboard: CommandCopying {
    func copy(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
    }
}

@MainActor
@Observable
final class CredentialSetupModel {
    private(set) var stage: CredentialSetupStage = .blockedByPrecondition
    private(set) var message: CredentialSetupMessage?
    private(set) var hasStoredCredential = false
    private(set) var waiting: AssistedSetupProgress?

    @ObservationIgnored private var discovery: ClaudeCodeDiscovery = .notFound
    @ObservationIgnored private var verification: Task<Void, Never>?
    @ObservationIgnored private var conduction: Task<AssistedSetupOutcome, Never>?

    private let store: any CredentialStoring
    private let verifier: any CredentialVerifying
    private let acquirer: any AssistedCredentialAcquiring
    private let claudeCode: @Sendable () async -> ClaudeCodeDiscovery
    private let credentialDidChange: @Sendable () async -> Void
    private let clipboard: any CommandCopying

    init(
        store: any CredentialStoring,
        verifier: any CredentialVerifying,
        acquirer: any AssistedCredentialAcquiring,
        claudeCode: @escaping @Sendable () async -> ClaudeCodeDiscovery,
        credentialDidChange: @escaping @Sendable () async -> Void,
        clipboard: any CommandCopying = SystemPasteboard()
    ) {
        self.store = store
        self.verifier = verifier
        self.acquirer = acquirer
        self.claudeCode = claudeCode
        self.credentialDidChange = credentialDidChange
        self.clipboard = clipboard
    }

    var content: CredentialSetupContent {
        let isConfigured = stage == .configured || stage == .configuredWithReservation
        let isAttempting = stage == .assisting || stage == .verifying
        let showsField = !isConfigured && stage != .verifying
        let saveIsBlockedBecause = saveBlockingReason()

        return CredentialSetupContent(
            stage: stage,
            title: CredentialSetupText.title,
            commandStep: CredentialSetupText.commandStep,
            steps: CredentialSetupText.steps,
            command: CredentialSetupText.command,
            copyCommandTitle: CredentialSetupText.copyCommand,
            fieldLabel: CredentialSetupText.fieldLabel,
            saveTitle: CredentialSetupText.save,
            cancelTitle: isAttempting ? CredentialSetupText.cancel : nil,
            replaceTitle: isConfigured ? CredentialSetupText.replace : nil,
            removeTitle: isConfigured ? CredentialSetupText.remove : nil,
            precondition: discovery.allowsProbe ? nil : CredentialSetupText.claudeCodeMissing,
            configuredNotice: isConfigured ? CredentialSetupText.configuredNotice : nil,
            message: message,
            showsField: showsField,
            canSave: showsField && saveIsBlockedBecause == nil,
            assistTitle: discovery.allowsProbe && !isAttempting ? CredentialSetupText.assist : nil,
            assistUnavailableReason: discovery.allowsProbe ? nil : CredentialSetupText.assistNeedsClaudeCode,
            codeFieldLabel: stage == .assisting ? CredentialSetupText.codeFieldLabel : nil,
            saveDisabledReason: showsField ? saveIsBlockedBecause : nil,
            costNotice: showsField || isAttempting ? CredentialSetupText.cost : nil,
            waitingNotice: waiting.map(CredentialSetupText.waiting(at:))
        )
    }

    func refresh() async {
        guard stage != .verifying, stage != .assisting else { return }

        discovery = await claudeCode()
        message = nil

        switch await store.isConfigured() {
        case let .success(configured):
            hasStoredCredential = configured
        case .failure:
            hasStoredCredential = false
            message = CredentialSetupText.keychainReadRefused
        }

        stage = restingStage()
    }

    func save(_ pasted: String) async {
        guard stage != .verifying else { return }
        guard discovery.allowsProbe else {
            message = CredentialSetupText.message(for: VerificationOutcome.claudeCodeNotFound)
            stage = .blockedByPrecondition
            return
        }

        guard pasted.contains(where: { !$0.isWhitespace }) else { return }

        guard let token = SubscriptionToken(pasted: pasted) else {
            message = Self.hasShapeOfAuthorizationCode(pasted)
                ? CredentialSetupText.codeInCredentialField
                : CredentialSetupText.malformedValue
            return
        }

        guard stage != .assisting else { return }

        await verify(token, fallingBackTo: restingStage(), obtainedByAssistance: false)
    }

    func assist() async {
        guard stage != .verifying, stage != .assisting, discovery.allowsProbe else { return }

        let resting = restingStage()
        message = nil
        stage = .assisting
        waiting = .launching

        let conduction = Task { [acquirer] in
            await acquirer.acquire { reached in
                Task { @MainActor [weak self] in self?.waiting = reached }
            }
        }
        self.conduction = conduction

        let outcome = await withTaskCancellationHandler {
            await conduction.value
        } onCancel: {
            conduction.cancel()
        }
        self.conduction = nil
        waiting = nil

        switch outcome {
        case .obtained(let token):
            await verify(token, fallingBackTo: resting, obtainedByAssistance: true)
        case .cancelled:
            stage = resting
        case .unavailable(let cause):
            if cause == .claudeCodeNotFound { discovery = .notFound }
            message = CredentialSetupText.message(for: cause)
            stage = restingStage()
        }
    }

    func submitCode(_ pasted: String) async {
        guard stage == .assisting, pasted.contains(where: { !$0.isWhitespace }) else { return }

        switch await acquirer.submit(code: pasted) {
        case .delivered:
            message = nil
        case .rejectedAsCredential:
            message = CredentialSetupText.credentialInCodeField
        case .noLiveConduction:
            break
        }
    }

    func remove() async {
        guard case .success = await store.remove() else {
            message = CredentialSetupText.keychainRemoveRefused
            return
        }

        hasStoredCredential = false
        message = CredentialSetupText.removed
        stage = restingStage()
        await credentialDidChange()
    }

    func beginReplacement() {
        guard stage != .verifying, stage != .assisting else { return }
        message = nil
        stage = discovery.allowsProbe ? .empty : .blockedByPrecondition
    }

    func cancel() {
        verification?.cancel()
        verification = nil
        conduction?.cancel()
        conduction = nil
    }

    func copyCommand() {
        clipboard.copy(CredentialSetupText.command)
    }

    private func verify(
        _ token: SubscriptionToken,
        fallingBackTo resting: CredentialSetupStage,
        obtainedByAssistance: Bool
    ) async {
        stage = .verifying
        message = nil

        let verification = Task { [verifier] in
            let outcome = await verifier.verify(token)
            guard !Task.isCancelled else {
                self.stage = resting
                return
            }
            await self.apply(outcome, of: token, fallingBackTo: resting, obtainedByAssistance: obtainedByAssistance)
        }

        self.verification = verification
        await withTaskCancellationHandler {
            await verification.value
        } onCancel: {
            verification.cancel()
        }
    }

    private func apply(
        _ outcome: VerificationOutcome,
        of token: SubscriptionToken,
        fallingBackTo resting: CredentialSetupStage,
        obtainedByAssistance: Bool
    ) async {
        if outcome.shouldPersist {
            guard case .success = await store.store(token) else {
                message = CredentialSetupText.keychainWriteRefused
                stage = resting
                return
            }
            hasStoredCredential = true
            await credentialDidChange()
        }

        message = CredentialSetupText.message(for: outcome, obtainedByAssistance: obtainedByAssistance)
        stage = stageAfter(outcome)
    }

    private func stageAfter(_ outcome: VerificationOutcome) -> CredentialSetupStage {
        switch outcome {
        case .success:
            .configured
        case .blockedByPolicy, .communicationFailure:
            .configuredWithReservation
        case .claudeCodeNotFound:
            .blockedByPrecondition
        case .credentialRejected, .credentialExpired, .unexpectedResponse:
            hasStoredCredential ? .configured : .refused
        }
    }

    private func restingStage() -> CredentialSetupStage {
        guard discovery.allowsProbe else { return .blockedByPrecondition }
        return hasStoredCredential ? .configured : .empty
    }

    private func saveBlockingReason() -> String? {
        if !discovery.allowsProbe { return CredentialSetupText.saveNeedsClaudeCode }
        if stage == .assisting { return CredentialSetupText.saveBusyWithAssistance }
        return nil
    }

    private static func hasShapeOfAuthorizationCode(_ pasted: String) -> Bool {
        pasted.trimmingCharacters(in: .whitespacesAndNewlines).contains("#")
    }
}
