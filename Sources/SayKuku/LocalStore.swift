import Foundation
import os

enum LocalStoreError: LocalizedError {
    case unreadableSnapshot
    case invalidAudioFilename

    var errorDescription: String? {
        localized("Couldn’t read local data. Restart SayKuku and try again.")
    }
}

actor LocalStore {
    struct Snapshot: Codable {
        static let currentVersion = 1

        var version = Snapshot.currentVersion
        var history: [HistoryEntry] = []
        var entities: [KnowledgeEntity] = []
        var corrections: [CorrectionRecord] = []
    }

    /// How a damaged `store.json` was handled at launch. The original bytes are never overwritten.
    enum DataIssue: Equatable, Sendable {
        /// Some records could not be decoded and were skipped; the untouched original was copied to `backup`.
        case skippedRecords(count: Int, backup: URL)
        /// The file could not be read at all; it was moved to `backup` and an empty store was started.
        case movedAside(backup: URL)
        /// The file could not be read from disk or backed up, or a newer SayKuku wrote it,
        /// so the store stays read-only to protect it.
        case readOnly(file: URL)

        var fileURL: URL {
            switch self {
            case .skippedRecords(_, let backup), .movedAside(let backup): backup
            case .readOnly(let file): file
            }
        }
    }

    private let root: URL
    private let snapshotURL: URL
    private let audioDirectory: URL
    private var loaded: LoadResult?
    private var latestGeneration = 0

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(StorageIdentity().directoryName, isDirectory: true)
        self.root = base
        snapshotURL = base.appendingPathComponent("store.json")
        audioDirectory = base.appendingPathComponent("Audio", isDirectory: true)
    }

    var dataIssue: DataIssue? { loadedSnapshot().issue }

    func load() throws -> Snapshot {
        let result = loadedSnapshot()
        guard result.isReadable else { throw LocalStoreError.unreadableSnapshot }
        return result.snapshot
    }

    func replace(_ newValue: Snapshot, generation: Int? = nil) throws {
        guard loadedSnapshot().isReadable else { throw LocalStoreError.unreadableSnapshot }
        if let generation, generation < latestGeneration { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        do {
            try prepareDirectories()
            try encoder.encode(newValue).write(to: snapshotURL, options: .atomic)
            try restrictPermissions(at: snapshotURL, to: 0o600)
        } catch {
            Log.store.error("Saving store.json failed: \(Log.describe(error), privacy: .public)")
            throw error
        }
        if let generation { latestGeneration = generation }
        loaded?.snapshot = newValue
    }

    func saveAudio(_ wavData: Data, id: UUID) throws -> String {
        guard loadedSnapshot().isReadable else { throw LocalStoreError.unreadableSnapshot }
        let name = "\(id.uuidString).wav"
        let url = audioDirectory.appendingPathComponent(name)
        do {
            try prepareDirectories()
            try wavData.write(to: url, options: .atomic)
            try restrictPermissions(at: url, to: 0o600)
        } catch {
            Log.store.error("Saving a recording failed: \(Log.describe(error), privacy: .public)")
            throw error
        }
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

    /// Where files from the old encrypted format remain, if any. They are never read, migrated, or deleted here.
    func legacyEncryptedDataURL() -> URL? {
        let files = FileManager.default
        let legacySnapshot = root.appendingPathComponent("store.data")
        if files.fileExists(atPath: legacySnapshot.path) { return legacySnapshot }
        let audio = (try? files.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil)) ?? []
        return audio.contains { $0.pathExtension == "audio" } ? audioDirectory : nil
    }

    /// Reads `store.json` on first use instead of in `init`, so launch never decodes it on the main thread.
    /// This runs before any write, so no recording being saved can be mistaken for a leftover.
    private func loadedSnapshot() -> LoadResult {
        if let loaded { return loaded }
        let result = Self.loadSnapshot(from: snapshotURL)
        Self.log(result)
        loaded = result
        if result.isReadable { removeUnreferencedAudio(keeping: result.snapshot.history) }
        return result
    }

    /// Deletes recordings left behind by a crash or a failed delete. Recordings named in a backup of
    /// damaged data are kept, so restoring the backup brings them back.
    private func removeUnreferencedAudio(keeping history: [HistoryEntry]) {
        let files = FileManager.default
        var referenced = Set(history.compactMap(\.audioFilename))
        let rootNames = (try? files.contentsOfDirectory(atPath: root.path)) ?? []
        for name in rootNames where name.hasPrefix("store.corrupt-") {
            // Scan the raw text, since a backup may not parse. If one can't be read, keep everything.
            guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return }
            let text = String(decoding: data, as: UTF8.self)
            referenced.formUnion(text.matches(of: /[0-9A-Fa-f-]{36}\.wav/).map { String($0.output) })
        }
        let audio = (try? files.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in audio where url.pathExtension == "wav" && !referenced.contains(url.lastPathComponent) {
            try? files.removeItem(at: url)
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

    private struct LoadResult {
        var snapshot = Snapshot()
        var isReadable = true
        var issue: DataIssue?
    }

    private static func loadSnapshot(from url: URL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return LoadResult() }
        // A read failure says nothing about the contents, so leave the file where it is.
        guard let data = try? Data(contentsOf: url) else {
            return LoadResult(isReadable: false, issue: .readOnly(file: url))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        if let decoded = try? decoder.decode(TolerantSnapshot.self, from: data) {
            // Saving would drop whatever a newer version added, so leave its file alone.
            guard decoded.snapshot.version <= Snapshot.currentVersion else {
                return LoadResult(isReadable: false, issue: .readOnly(file: url))
            }
            guard decoded.skippedCount > 0 else { return LoadResult(snapshot: decoded.snapshot) }
            // Copy rather than move: the next save rewrites store.json without the skipped records.
            guard let backup = try? backUp(url, keepingOriginal: true) else {
                return LoadResult(isReadable: false, issue: .readOnly(file: url))
            }
            return LoadResult(
                snapshot: decoded.snapshot,
                issue: .skippedRecords(count: decoded.skippedCount, backup: backup)
            )
        }
        guard let backup = try? backUp(url, keepingOriginal: false) else {
            return LoadResult(isReadable: false, issue: .readOnly(file: url))
        }
        return LoadResult(issue: .movedAside(backup: backup))
    }

    /// Only counts and the backup's file name: full paths contain the user name.
    private static func log(_ result: LoadResult) {
        let snapshot = result.snapshot
        let counts = "history \(snapshot.history.count), knowledge \(snapshot.entities.count), "
            + "corrections \(snapshot.corrections.count)"
        switch result.issue {
        case nil:
            Log.store.info("Loaded store.json: \(counts, privacy: .public)")
        case .skippedRecords(let count, let backup):
            let backupName = backup.lastPathComponent
            Log.store.notice(
                "Loaded store.json: \(counts, privacy: .public); skipped \(count, privacy: .public) damaged records, original copied to \(backupName, privacy: .public)"
            )
        case .movedAside(let backup):
            let backupName = backup.lastPathComponent
            Log.store.error("store.json unreadable; moved to \(backupName, privacy: .public), starting empty")
        case .readOnly:
            Log.store.error("store.json unreadable, not backed up or from a newer version; staying read-only")
        }
    }

    /// Saves the file as `store.corrupt-<timestamp>.json` next to it, never replacing an existing backup.
    private static func backUp(_ url: URL, keepingOriginal: Bool) throws -> URL {
        let files = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let directory = url.deletingLastPathComponent()
        var backup = directory.appendingPathComponent("store.corrupt-\(stamp).json")
        var suffix = 2
        while files.fileExists(atPath: backup.path) {
            backup = directory.appendingPathComponent("store.corrupt-\(stamp)-\(suffix).json")
            suffix += 1
        }
        if keepingOriginal {
            try files.copyItem(at: url, to: backup)
        } else {
            try files.moveItem(at: url, to: backup)
        }
        return backup
    }
}

/// Decodes each record on its own so one damaged or newer-format record does not hide the rest.
/// Keys it doesn't list, such as `sessions` from builds that saved Voice Agent turns, are ignored
/// and dropped at the next save.
private struct TolerantSnapshot: Decodable {
    let snapshot: LocalStore.Snapshot
    let skippedCount: Int

    private enum CodingKeys: String, CodingKey {
        case version, history, entities, corrections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var skipped = 0
        func records<Record: Decodable>(_ key: CodingKeys) throws -> [Record] {
            let decoded = try container.decodeIfPresent([Lossy<Record>].self, forKey: key) ?? []
            skipped += decoded.filter { $0.value == nil }.count
            return decoded.compactMap(\.value)
        }
        snapshot = try LocalStore.Snapshot(
            // Files written before versioning have no version and count as version 1.
            version: container.decodeIfPresent(Int.self, forKey: .version) ?? 1,
            history: records(.history),
            entities: records(.entities),
            corrections: records(.corrections)
        )
        skippedCount = skipped
    }
}
