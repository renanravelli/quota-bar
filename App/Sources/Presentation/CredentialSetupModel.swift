import AppKit
import Foundation
import Observation
import QuotaBarCore
import QuotaBarTransport

enum CredentialSetupStage: Equatable {
    case blockedByPrecondition
    case empty
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

    @ObservationIgnored private var discovery: ClaudeCodeDiscovery = .notFound
    @ObservationIgnored private var verification: Task<Void, Never>?

    private let store: any CredentialStoring
    private let verifier: any CredentialVerifying
    private let claudeCode: @Sendable () async -> ClaudeCodeDiscovery
    private let credentialDidChange: @Sendable () async -> Void
    private let clipboard: any CommandCopying

    init(
        store: any CredentialStoring,
        verifier: any CredentialVerifying,
        claudeCode: @escaping @Sendable () async -> ClaudeCodeDiscovery,
        credentialDidChange: @escaping @Sendable () async -> Void,
        clipboard: any CommandCopying = SystemPasteboard()
    ) {
        self.store = store
        self.verifier = verifier
        self.claudeCode = claudeCode
        self.credentialDidChange = credentialDidChange
        self.clipboard = clipboard
    }

    var content: CredentialSetupContent {
        let showsField = stage == .empty || stage == .refused
        let isConfigured = stage == .configured || stage == .configuredWithReservation

        return CredentialSetupContent(
            stage: stage,
            title: CredentialSetupText.title,
            commandStep: CredentialSetupText.commandStep,
            steps: CredentialSetupText.steps,
            command: CredentialSetupText.command,
            copyCommandTitle: CredentialSetupText.copyCommand,
            fieldLabel: CredentialSetupText.fieldLabel,
            saveTitle: CredentialSetupText.save,
            cancelTitle: stage == .verifying ? CredentialSetupText.cancel : nil,
            replaceTitle: isConfigured ? CredentialSetupText.replace : nil,
            removeTitle: isConfigured ? CredentialSetupText.remove : nil,
            precondition: discovery.allowsProbe ? nil : CredentialSetupText.claudeCodeMissing,
            configuredNotice: isConfigured ? CredentialSetupText.configuredNotice : nil,
            message: message,
            showsField: showsField,
            canSave: showsField && discovery.allowsProbe
        )
    }

    func refresh() async {
        guard stage != .verifying else { return }

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
            message = CredentialSetupText.message(for: .claudeCodeNotFound)
            stage = .blockedByPrecondition
            return
        }

        guard pasted.contains(where: { !$0.isWhitespace }) else { return }

        guard let token = SubscriptionToken(pasted: pasted) else {
            message = CredentialSetupText.malformedValue
            return
        }

        let resting = restingStage()
        stage = .verifying
        message = nil

        let verification = Task { [verifier] in
            let outcome = await verifier.verify(token)
            guard !Task.isCancelled else {
                self.stage = resting
                return
            }
            await self.apply(outcome, of: token, fallingBackTo: resting)
        }

        self.verification = verification
        await verification.value
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
        guard stage != .verifying else { return }
        message = nil
        stage = discovery.allowsProbe ? .empty : .blockedByPrecondition
    }

    func cancel() {
        verification?.cancel()
        verification = nil
    }

    func copyCommand() {
        clipboard.copy(CredentialSetupText.command)
    }

    private func apply(
        _ outcome: VerificationOutcome,
        of token: SubscriptionToken,
        fallingBackTo resting: CredentialSetupStage
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

        message = CredentialSetupText.message(for: outcome)
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
}
