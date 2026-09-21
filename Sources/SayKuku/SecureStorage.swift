import CryptoKit
import Foundation
import Security

enum SecureStorageError: LocalizedError {
    case keychain(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .keychain(let status): "Keychain error (\(status))"
        case .invalidData: "Stored data is invalid"
        }
    }
}

struct KeychainStore: Sendable {
    private static let releaseBundleIdentifier = "com.saykuku.app"

    private let service: String
    private let legacyServices: [String]

    init() {
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let isDevelopmentBuild = bundleIdentifier == "com.saykuku.dev"
        service = isDevelopmentBuild ? "com.saykuku.dev.secure-storage" : "com.saykuku.app.secure-storage"
        legacyServices = isDevelopmentBuild ? [] : [Self.releaseBundleIdentifier]
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
            let status = SecItemDelete(baseQuery(account, service: itemService) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecureStorageError.keychain(status)
            }
        }
    }

    func data(for account: String) throws -> Data? {
        guard let value = try string(for: account) else { return nil }
        return Data(base64Encoded: value)
    }

    func set(_ data: Data, for account: String) throws {
        try set(data.base64EncodedString(), for: account)
    }

    func setIfMissing(_ data: Data, for account: String) throws -> Bool {
        var item = baseQuery(account, service: service)
        item[kSecValueData as String] = Data(data.base64EncodedString().utf8)
        item[kSecAttrLabel as String] = "SayKuku"
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw SecureStorageError.keychain(status) }
        return true
    }

    private func baseQuery(_ account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

actor LocalStore {
    struct Snapshot: Codable {
        var history: [HistoryEntry] = []
        var entities: [KnowledgeEntity] = []
        var relationships: [KnowledgeRelationship] = []
        var corrections: [CorrectionRecord] = []
        var sessions: [AgentSession] = []
    }

    private let root: URL
    private let snapshotURL: URL
    private let audioDirectory: URL
    private let keychain: KeychainStore
    private var snapshot: Snapshot
    private var latestGeneration = 0

    init(root: URL? = nil, keychain: KeychainStore = KeychainStore()) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SayKuku", isDirectory: true)
        self.root = base
        snapshotURL = base.appendingPathComponent("store.data")
        audioDirectory = base.appendingPathComponent("Audio", isDirectory: true)
        self.keychain = keychain
        snapshot = Self.loadSnapshot(from: snapshotURL, keychain: keychain)
    }

    func load() -> Snapshot { snapshot }

    func replace(_ newValue: Snapshot, generation: Int? = nil) throws {
        if let generation {
            guard generation >= latestGeneration else { return }
            latestGeneration = generation
        }
        snapshot = newValue
        try persist()
    }

    func saveAudio(_ wavData: Data, id: UUID) throws -> String {
        try prepareDirectories()
        let key = try encryptionKey()
        let sealed = try AES.GCM.seal(wavData, using: key)
        guard let combined = sealed.combined else { throw SecureStorageError.invalidData }
        let name = "\(id.uuidString).audio"
        try combined.write(to: audioDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    func audio(named filename: String) throws -> Data {
        let encrypted = try Data(contentsOf: audioDirectory.appendingPathComponent(filename))
        let box = try AES.GCM.SealedBox(combined: encrypted)
        return try AES.GCM.open(box, using: encryptionKey())
    }

    func removeAudio(named filename: String) throws {
        let url = audioDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func persist() throws {
        try prepareDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let plaintext = try encoder.encode(snapshot)
        let sealed = try AES.GCM.seal(plaintext, using: encryptionKey())
        guard let encrypted = sealed.combined else { throw SecureStorageError.invalidData }
        try encrypted.write(to: snapshotURL, options: .atomic)
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    }

    private func encryptionKey() throws -> SymmetricKey {
        try Self.encryptionKey(keychain: keychain)
    }

    private static func encryptionKey(keychain: KeychainStore) throws -> SymmetricKey {
        let account = "history-encryption-key"
        if let data = try keychain.data(for: account), data.count == 32 { return SymmetricKey(data: data) }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw SecureStorageError.keychain(status) }
        let data = Data(bytes)
        if try keychain.setIfMissing(data, for: account) { return SymmetricKey(data: data) }
        guard let existing = try keychain.data(for: account), existing.count == 32 else {
            throw SecureStorageError.invalidData
        }
        return SymmetricKey(data: existing)
    }

    private static func loadSnapshot(from url: URL, keychain: KeychainStore) -> Snapshot {
        guard let encrypted = try? Data(contentsOf: url),
              let key = try? encryptionKey(keychain: keychain),
              let box = try? AES.GCM.SealedBox(combined: encrypted),
              let data = try? AES.GCM.open(box, using: key) else { return Snapshot() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode(Snapshot.self, from: data)) ?? Snapshot()
    }
}
