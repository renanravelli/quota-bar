import QuotaBarCore

public protocol CredentialVerifying: Sendable {
    func verify(_ token: SubscriptionToken) async -> VerificationOutcome
}
