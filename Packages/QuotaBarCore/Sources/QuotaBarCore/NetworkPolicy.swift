public enum ProbeReaction: Sendable, Hashable {
    case keepCadence
    case widenCadence
    case stopProbing
}

public enum NetworkPolicy {
    public static func reaction(to reason: FailureReason, withinWakeTolerance: Bool) -> ProbeReaction {
        switch reason {
        case .credentialRejected, .credentialExpired, .credentialUnreadable, .blockedByPolicy, .claudeCodeNotFound:
            .stopProbing
        case .communicationFailure:
            withinWakeTolerance ? .keepCadence : .widenCadence
        case .unexpectedResponse:
            .keepCadence
        }
    }
}
