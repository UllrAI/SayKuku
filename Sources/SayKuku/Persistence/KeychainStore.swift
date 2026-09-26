import Foundation
import Security

enum SecureStorageError: LocalizedError, Equatable {
    case keychain(OSStatus)
    case invalidData
    case readUnavailable

    var errorDescription: String? {
        switch self {
        case .keychain, .invalidData: localized("Couldn’t save the API Key. Check Keychain on this Mac.")
        case .readUnavailable: localized("Couldn’t read the API Key from this Mac’s Keychain. Try again before editing it.")
        }
    }
}

enum StorageIdentity: Equatable {
    case release
    case development

    init(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self = bundleIdentifier == "com.saykuku.app" ? .release : .development
    }

    var service: String {
        switch self {
        case .release: "com.saykuku.app.secure-storage"
        case .development: "com.saykuku.dev.secure-storage"
        }
    }

    var directoryName: String {
        switch self {
        case .release: "SayKuku"
        case .development: "SayKuku Dev"
        }
    }
}

struct KeychainStore: Sendable {
    private let service: String
    private let legacyServices: [String]

    init() {
        let identity = StorageIdentity()
        service = identity.service
        legacyServices = identity == .release ? ["com.saykuku.app"] : []
    }

    init(service: String, legacyServices: [String] = []) {
        self.service = service
        self.legacyServices = legacyServices.filter { $0 != service }
    }

    func string(for account: String) throws -> String? {
        if let value = try readString(for: account, service: service) { return value }

        for legacyService in legacyServices {
            guard let value = try readString(for: account, service: legacyService) else { continue }
            try set(value, for: account)
            // The value is already migrated, so a failed delete must not block reading; `remove(_:)` clears it later.
            try? delete(account, service: legacyService)
            return value
        }
        return nil
    }

    private func readString(for account: String, service: String) throws -> String? {
        var query = baseQuery(account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecureStorageError.keychain(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SecureStorageError.invalidData
        }
        return value
    }

    func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account, service: service)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "SayKuku"
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                let retryStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
                guard retryStatus == errSecSuccess else { throw SecureStorageError.keychain(retryStatus) }
            } else if addStatus != errSecSuccess {
                throw SecureStorageError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw SecureStorageError.keychain(status)
        }
    }

    func remove(_ account: String) throws {
        for itemService in legacyServices + [service] {
            try delete(account, service: itemService)
        }
    }

    private func delete(_ account: String, service: String) throws {
        let status = SecItemDelete(baseQuery(account, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.keychain(status)
        }
    }

    private func baseQuery(_ account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
