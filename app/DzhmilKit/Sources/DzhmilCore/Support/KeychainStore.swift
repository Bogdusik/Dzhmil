import Foundation
import Security

public struct KeychainStore: Sendable {
    public let service: String
    public let account: String

    public init(service: String = "com.bogdusik.dzhmil", account: String = "anthropic-api-key") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read() -> String? {
        guard case .found(let key) = lookup() else { return nil }
        return key
    }

    public func lookup() -> StoredKey {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return StoredKey.from(status: status, data: item as? Data)
    }

    public func save(_ value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public enum StoredKey: Equatable, Sendable {
    case found(String), missing, blocked

    static func from(status: OSStatus, data: Data?) -> StoredKey {
        switch status {
        case errSecSuccess: data.flatMap { String(data: $0, encoding: .utf8) }.map(StoredKey.found) ?? .missing
        case errSecItemNotFound: .missing
        default: .blocked
        }
    }

    public func value() throws -> String? {
        switch self {
        case .found(let key): key
        case .missing: nil
        case .blocked: throw ChatError.keyBlocked
        }
    }
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}
