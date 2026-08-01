public enum AssistedSetupProgress: Sendable, Hashable {
    case launching
    case waitingForApproval
}

public enum AssistedSetupUnavailability: Sendable, Hashable, CaseIterable {
    case claudeCodeNotFound
    case launchFailed
    case refusedByPolicy
    case silentBeforeAnySign
    case endedWithoutCredential
    case approvalTimedOut

    public var mayMentionBrowserOrCode: Bool {
        switch self {
        case .claudeCodeNotFound, .launchFailed, .silentBeforeAnySign: false
        case .refusedByPolicy, .endedWithoutCredential, .approvalTimedOut: true
        }
    }
}

public enum AssistedSetupOutcome: Sendable {
    case obtained(SubscriptionToken)
    case cancelled
    case unavailable(AssistedSetupUnavailability)
}

public enum CodeSubmission: Sendable, Hashable {
    case delivered
    case rejectedAsCredential
    case noLiveConduction
}

public struct AssistedSetupTiming: Sendable, Hashable {
    public static let standard = AssistedSetupTiming(
        firstOutput: .seconds(20),
        total: .seconds(180),
        terminationGrace: .seconds(2),
        pollInterval: .seconds(1)
    )

    public let firstOutput: Duration
    public let total: Duration
    public let terminationGrace: Duration
    public let pollInterval: Duration

    public init(firstOutput: Duration, total: Duration, terminationGrace: Duration, pollInterval: Duration) {
        self.firstOutput = firstOutput
        self.total = total
        self.terminationGrace = terminationGrace
        self.pollInterval = pollInterval
    }
}

public protocol AssistedCredentialAcquiring: Sendable {
    func acquire(
        onProgress: @escaping @Sendable (AssistedSetupProgress) -> Void
    ) async -> AssistedSetupOutcome

    func submit(code: String) async -> CodeSubmission
}
