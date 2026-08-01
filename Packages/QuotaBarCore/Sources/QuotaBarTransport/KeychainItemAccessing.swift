import Foundation
import Security

protocol KeychainItemAccessing: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func matchExists(_ query: [String: Any]) -> OSStatus
    func copyData(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychain: KeychainItemAccessing {
    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func matchExists(_ query: [String: Any]) -> OSStatus {
        SecItemCopyMatching(query as CFDictionary, nil)
    }

    func copyData(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        return (status, found as? Data)
    }

    func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
