import CryptoKit
import Foundation
import Security

enum SecureStorageError: LocalizedError {
    case keychain(OSStatus)
    case invalidData
    case unreadableSnapshot

    var errorDescription: String? {
        switch self {
        case .keychain(let status): "Keychain error (\(status))"
        case .invalidData: "Stored data is invalid"
        case .unreadableSnapshot: "Stored data could not be read; changes were not saved"
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
    private let snapshotIsReadable: Bool
    private var latestGeneration = 0

    init(root: URL? = nil, keychain: KeychainStore = KeychainStore()) {
        let base: URL
        if let root {
            base = root
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let identity = StorageIdentity()
            base = support.appendingPathComponent(identity.directoryName, isDirectory: true)
            if identity == .development {
                Self.migrateDevelopmentDataIfNeeded(
                    from: support.appendingPathComponent("SayKuku", isDirectory: true),
                    to: base,
                    keychain: keychain
                )
            }
        }
        self.root = base
        snapshotURL = base.appendingPathComponent("store.data")
        audioDirectory = base.appendingPathComponent("Audio", isDirectory: true)
        self.keychain = keychain
        (snapshot, snapshotIsReadable) = Self.loadSnapshot(from: snapshotURL, keychain: keychain)
    }

    func load() throws -> Snapshot {
        guard snapshotIsReadable else { throw SecureStorageError.unreadableSnapshot }
        return snapshot
    }

    func replace(_ newValue: Snapshot, generation: Int? = nil) throws {
        guard snapshotIsReadable else { throw SecureStorageError.unreadableSnapshot }
        if let generation {
            guard generation >= latestGeneration else { return }
            latestGeneration = generation
        }
        try persist(newValue)
        snapshot = newValue
    }

    func saveAudio(_ wavData: Data, id: UUID) throws -> String {
        guard snapshotIsReadable else { throw SecureStorageError.unreadableSnapshot }
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

    private func persist(_ value: Snapshot) throws {
        try prepareDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let plaintext = try encoder.encode(value)
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

    static func migrateDevelopmentDataIfNeeded(from legacyRoot: URL, to destination: URL, keychain: KeychainStore) {
        let files = FileManager.default
        guard !files.fileExists(atPath: destination.path) else { return }
        let legacySnapshot = legacyRoot.appendingPathComponent("store.data")
        guard files.fileExists(atPath: legacySnapshot.path) else { return }
        let (snapshot, readable) = loadSnapshot(from: legacySnapshot, keychain: keychain)
        guard readable else { return }

        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".SayKuku-Dev-\(UUID().uuidString)", isDirectory: true)
        do {
            try files.createDirectory(at: staging, withIntermediateDirectories: true)
            try files.copyItem(at: legacySnapshot, to: staging.appendingPathComponent("store.data"))
            let audioNames = Set(snapshot.history.compactMap(\.audioFilename))
            if !audioNames.isEmpty {
                let audioDirectory = staging.appendingPathComponent("Audio", isDirectory: true)
                try files.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
                for name in audioNames {
                    let source = legacyRoot.appendingPathComponent("Audio", isDirectory: true).appendingPathComponent(name)
                    if files.fileExists(atPath: source.path) {
                        try files.copyItem(at: source, to: audioDirectory.appendingPathComponent(name))
                    }
                }
            }
            try files.moveItem(at: staging, to: destination)
        } catch {
            try? files.removeItem(at: staging)
        }
    }

    private static func loadSnapshot(from url: URL, keychain: KeychainStore) -> (Snapshot, Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (Snapshot(), true) }
        guard let encrypted = try? Data(contentsOf: url),
              let key = try? encryptionKey(keychain: keychain),
              let box = try? AES.GCM.SealedBox(combined: encrypted),
              let data = try? AES.GCM.open(box, using: key) else { return (Snapshot(), false) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return (Snapshot(), false) }
        return (snapshot, true)
    }
}
