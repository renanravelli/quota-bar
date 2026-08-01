import Foundation
import Security

@testable import QuotaBarTransport

final class InMemoryKeychain: KeychainItemAccessing, @unchecked Sendable {
    enum Operation: Sendable {
        case add
        case matchExists
        case copyData
        case update
        case delete
    }

    struct Call {
        let operation: Operation
        let attributes: [String: Any]
    }

    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var forcedStatus: OSStatus?
    private var recorded: [Call] = []

    var calls: [Call] {
        lock.withLock { recorded }
    }

    var storedItemCount: Int {
        lock.withLock { items.count }
    }

    func failAllOperations(with status: OSStatus) {
        lock.withLock { forcedStatus = status }
    }

    func stopFailing() {
        lock.withLock { forcedStatus = nil }
    }

    func plant(_ data: Data, service: String, account: String) {
        lock.withLock { items[Self.key(service: service, account: account)] = data }
    }

    func storedData(service: String, account: String) -> Data? {
        lock.withLock { items[Self.key(service: service, account: account)] }
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            record(.add, attributes)
            if let forcedStatus { return forcedStatus }
            guard let key = Self.key(from: attributes) else { return errSecParam }
            guard items[key] == nil else { return errSecDuplicateItem }
            items[key] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    func matchExists(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            record(.matchExists, query)
            if let forcedStatus { return forcedStatus }
            guard let key = Self.key(from: query) else { return errSecParam }
            return items[key] == nil ? errSecItemNotFound : errSecSuccess
        }
    }

    func copyData(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            record(.copyData, query)
            if let forcedStatus { return (forcedStatus, nil) }
            guard let key = Self.key(from: query) else { return (errSecParam, nil) }
            guard let data = items[key] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            record(.update, query.merging(attributes) { _, new in new })
            if let forcedStatus { return forcedStatus }
            guard let key = Self.key(from: query) else { return errSecParam }
            guard items[key] != nil else { return errSecItemNotFound }
            items[key] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            record(.delete, query)
            if let forcedStatus { return forcedStatus }
            guard let key = Self.key(from: query) else { return errSecParam }
            guard items.removeValue(forKey: key) != nil else { return errSecItemNotFound }
            return errSecSuccess
        }
    }

    private func record(_ operation: Operation, _ attributes: [String: Any]) {
        recorded.append(Call(operation: operation, attributes: attributes))
    }

    private static func key(from attributes: [String: Any]) -> String? {
        guard let service = attributes[kSecAttrService as String] as? String,
              let account = attributes[kSecAttrAccount as String] as? String
        else { return nil }
        return key(service: service, account: account)
    }

    private static func key(service: String, account: String) -> String {
        "\(service)\u{0}\(account)"
    }
}
