import Foundation

public enum KeychainOutcome<T: Sendable>: Sendable {
    case success(T)
    case failure(KeychainFailure)
}

public enum KeychainFailure: Sendable, Hashable {
    case itemNotFound
    case interactionNotAllowed
    case authorizationDenied
    case unexpected(OSStatus)
}

public protocol CredentialStoring: Sendable {
    func store(_ token: SubscriptionToken) async -> KeychainOutcome<Void>
    func load() async -> KeychainOutcome<SubscriptionToken>
    func remove() async -> KeychainOutcome<Void>
    func isConfigured() async -> KeychainOutcome<Bool>
}
