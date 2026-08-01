import QuotaBarCore

public struct ProbeCredentialVerifier: CredentialVerifying {
    private let probe: QuotaProbe
    private let locator: ClaudeCodeLocator
    private let time: any DateProviding

    public init(probe: QuotaProbe, locator: ClaudeCodeLocator, time: any DateProviding = SystemDate()) {
        self.probe = probe
        self.locator = locator
        self.time = time
    }

    public func verify(_ token: SubscriptionToken) async -> VerificationOutcome {
        guard let version = await locator.discover().version else { return .claudeCodeNotFound }

        return VerificationOutcome(
            probeResult: await probe.read(using: token, claudeCodeVersion: version, at: time.now)
        )
    }
}
