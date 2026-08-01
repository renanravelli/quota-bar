import Foundation

public enum FailureReason: Sendable, Hashable, CaseIterable {
    case credentialRejected
    case credentialExpired
    case credentialUnreadable
    case blockedByPolicy
    case claudeCodeNotFound
    case communicationFailure
    case unexpectedResponse
}

public enum AttemptOutcome: Sendable, Hashable {
    case inProgress
    case succeeded(at: Date)
    case failed(FailureReason)
}
