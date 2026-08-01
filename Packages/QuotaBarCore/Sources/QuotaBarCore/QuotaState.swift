public enum UnavailableField: Sendable, Hashable {
    case bindingWindow
    case overage
    case fallbackPercentage
    case resetAt(QuotaWindow)
    case utilization(QuotaWindow)
}

public enum ConfigurationPendency: Sendable, Hashable, CaseIterable {
    case credential
    case claudeCode
}

public struct QuotaState: Sendable {
    public let credentialPresent: Bool
    public let claudeCodeMissing: Bool
    public let snapshot: QuotaSnapshot?
    public let lastAttempt: AttemptOutcome
    public let cycle: CadenceCycle?
    public let maxIdleCadenceSinceReading: Duration
    public let source: QuotaSource?
    public let unavailableFields: Set<UnavailableField>

    public var pendencies: [ConfigurationPendency] {
        var declared: [ConfigurationPendency] = []
        if !credentialPresent { declared.append(.credential) }
        if claudeCodeMissing { declared.append(.claudeCode) }
        return declared
    }

    public init(
        credentialPresent: Bool,
        claudeCodeMissing: Bool = false,
        snapshot: QuotaSnapshot?,
        lastAttempt: AttemptOutcome = .inProgress,
        cycle: CadenceCycle?,
        maxIdleCadenceSinceReading: Duration,
        source: QuotaSource?,
        unavailableFields: Set<UnavailableField> = []
    ) {
        if case .succeeded = lastAttempt {
            precondition(snapshot != nil, "uma tentativa bem-sucedida produziu uma leitura: snapshot não pode ser nulo")
        }

        self.credentialPresent = credentialPresent
        self.claudeCodeMissing = claudeCodeMissing
        self.snapshot = snapshot
        self.lastAttempt = lastAttempt
        self.cycle = cycle
        self.maxIdleCadenceSinceReading = maxIdleCadenceSinceReading
        self.source = source
        self.unavailableFields = unavailableFields
    }
}

public extension QuotaState {
    static let unconfigured = QuotaState(
        credentialPresent: false,
        snapshot: nil,
        cycle: nil,
        maxIdleCadenceSinceReading: ScheduledCadence.floor,
        source: nil
    )
}
