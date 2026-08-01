public enum VerificationOutcome: Sendable, Hashable, CaseIterable {
    case success
    case credentialRejected
    case credentialExpired
    case blockedByPolicy
    case communicationFailure
    case unexpectedResponse
    case claudeCodeNotFound

    public var shouldPersist: Bool {
        switch self {
        case .success, .blockedByPolicy, .communicationFailure:
            true
        case .credentialRejected, .credentialExpired, .unexpectedResponse, .claudeCodeNotFound:
            false
        }
    }

    public init(probeResult: ProbeResult) {
        switch probeResult {
        case .reading:
            self = .success
        case .throttled:
            self = .communicationFailure
        case .failed(let reason):
            self.init(failureReason: reason)
        }
    }

    private init(failureReason: FailureReason) {
        switch failureReason {
        case .credentialRejected:
            self = .credentialRejected
        case .credentialExpired:
            self = .credentialExpired
        case .blockedByPolicy:
            self = .blockedByPolicy
        case .communicationFailure:
            self = .communicationFailure
        case .claudeCodeNotFound:
            self = .claudeCodeNotFound
        case .unexpectedResponse:
            self = .unexpectedResponse
        case .credentialUnreadable:
            self = .unexpectedResponse
        }
    }
}
