import Foundation

enum LocalStoreError: LocalizedError {
    case unreadableSnapshot
    case invalidAudioFilename

    var errorDescription: String? {
        switch self {
        case .unreadableSnapshot: "Local data could not be read; changes were not saved"
        case .invalidAudioFilename: "Invalid audio filename"
        }
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
    private var snapshot: Snapshot
    private let snapshotIsReadable: Bool
    private var latestGeneration = 0

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(StorageIdentity().directoryName, isDirectory: true)
        self.root = base
        snapshotURL = base.appendingPathComponent("store.json")
        audioDirectory = base.appendingPathComponent("Audio", isDirectory: true)
        (snapshot, snapshotIsReadable) = Self.loadSnapshot(from: snapshotURL)
    }

    func load() throws -> Snapshot {
        guard snapshotIsReadable else { throw LocalStoreError.unreadableSnapshot }
        return snapshot
    }

    func replace(_ newValue: Snapshot, generation: Int? = nil) throws {
        guard snapshotIsReadable else { throw LocalStoreError.unreadableSnapshot }
        if let generation, generation < latestGeneration { return }
        try prepareDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(newValue).write(to: snapshotURL, options: .atomic)
        try restrictPermissions(at: snapshotURL, to: 0o600)
        if let generation { latestGeneration = generation }
        snapshot = newValue
    }

    func saveAudio(_ wavData: Data, id: UUID) throws -> String {
        guard snapshotIsReadable else { throw LocalStoreError.unreadableSnapshot }
        try prepareDirectories()
        let name = "\(id.uuidString).wav"
        let url = audioDirectory.appendingPathComponent(name)
        try wavData.write(to: url, options: .atomic)
        try restrictPermissions(at: url, to: 0o600)
        return name
    }

    func audio(named filename: String) throws -> Data {
        try Data(contentsOf: audioURL(named: filename))
    }

    func removeAudio(named filename: String) throws {
        let url = try audioURL(named: filename)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func audioURL(named filename: String) throws -> URL {
        let name = URL(fileURLWithPath: filename)
        guard name.lastPathComponent == filename,
              name.pathExtension == "wav",
              UUID(uuidString: name.deletingPathExtension().lastPathComponent) != nil else {
            throw LocalStoreError.invalidAudioFilename
        }
        return audioDirectory.appendingPathComponent(filename)
    }

    private func prepareDirectories() throws {
        let files = FileManager.default
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        try files.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try restrictPermissions(at: root, to: 0o700)
        try restrictPermissions(at: audioDirectory, to: 0o700)
    }

    private func restrictPermissions(at url: URL, to permissions: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private static func loadSnapshot(from url: URL) -> (Snapshot, Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (Snapshot(), true) }
        guard let data = try? Data(contentsOf: url) else { return (Snapshot(), false) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let value = try? decoder.decode(Snapshot.self, from: data) else { return (Snapshot(), false) }
        return (value, true)
    }
}
