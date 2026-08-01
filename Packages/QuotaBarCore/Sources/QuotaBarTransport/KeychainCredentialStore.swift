import Foundation
import Security

public struct KeychainCredentialStore: CredentialStoring {
    static let service = "com.renanravelli.QuotaBar"
    static let account = "subscription-token"

    private let keychain: any KeychainItemAccessing

    public init() {
        self.init(keychain: SystemKeychain())
    }

    init(keychain: any KeychainItemAccessing) {
        self.keychain = keychain
    }

    public func store(_ token: SubscriptionToken) async -> KeychainOutcome<Void> {
        let value = token.withValue { Data($0.utf8) }
        var newItem = itemQuery
        newItem.merge(attributes(for: value)) { _, new in new }

        let status = keychain.add(newItem)
        guard status == errSecDuplicateItem else { return outcome(of: status) }

        return outcome(of: keychain.update(itemQuery, with: attributes(for: value)))
    }

    public func load() async -> KeychainOutcome<SubscriptionToken> {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (status, data) = keychain.copyData(query)
        guard status == errSecSuccess else { return .failure(KeychainFailure(status: status)) }

        guard let data,
              let pasted = String(data: data, encoding: .utf8),
              let token = SubscriptionToken(pasted: pasted)
        else { return .failure(.unexpected(errSecDecode)) }

        return .success(token)
    }

    public func remove() async -> KeychainOutcome<Void> {
        outcome(of: keychain.delete(itemQuery))
    }

    public func isConfigured() async -> KeychainOutcome<Bool> {
        var query = itemQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        switch keychain.matchExists(query) {
        case errSecSuccess: return .success(true)
        case errSecItemNotFound: return .success(false)
        case let status: return .failure(KeychainFailure(status: status))
        }
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func attributes(for value: Data) -> [String: Any] {
        [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
    }

    private func outcome(of status: OSStatus) -> KeychainOutcome<Void> {
        status == errSecSuccess ? .success(()) : .failure(KeychainFailure(status: status))
    }
}

extension KeychainFailure {
    init(status: OSStatus) {
        switch status {
        case errSecItemNotFound: self = .itemNotFound
        case errSecInteractionNotAllowed: self = .interactionNotAllowed
        case errSecAuthFailed, errSecUserCanceled: self = .authorizationDenied
        default: self = .unexpected(status)
        }
    }
}
