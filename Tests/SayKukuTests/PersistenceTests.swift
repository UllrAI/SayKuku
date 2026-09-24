import Foundation
import Testing
@testable import SayKuku

/// Recordings are removed in a background task, so poll briefly instead of asserting immediately.
private func waitForRemoval(of url: URL) async -> Bool {
    for _ in 0..<100 {
        if !FileManager.default.fileExists(atPath: url.path) { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

@Suite("Configuration and persistence")
struct PersistenceTests {
    @Test("only the release bundle uses production storage")
    func storageIdentity() {
        let release = StorageIdentity(bundleIdentifier: "com.saykuku.app")
        #expect(release.service == "com.saykuku.app.secure-storage")
        #expect(release.directoryName == "SayKuku")

        for bundleIdentifier in ["com.saykuku.dev", "com.example.other", nil] {
            let development = StorageIdentity(bundleIdentifier: bundleIdentifier)
            #expect(development.service == "com.saykuku.dev.secure-storage")
            #expect(development.directoryName == "SayKuku Dev")
        }
    }

    @Test("regional endpoint uses legacy or workspace host")
    func endpoints() {
        var config = QwenConfiguration(region: .beijing, workspaceID: "", realtimeModel: "r", reasoningModel: "m")
        #expect(config.realtimeURL?.host == "dashscope.aliyuncs.com")
        config.workspaceID = "ws123"
        #expect(config.chatCompletionsURL?.host == "ws123.cn-beijing.maas.aliyuncs.com")
    }

    @Test("dictation preferences persist across app state reloads")
    @MainActor
    func dictationPreferencePersistence() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }

        let state = environment.makeState()
        #expect(state.automaticAgentWriteBack)
        state.recognitionLanguage = .english
        state.dictationNumberFormat = .spoken
        state.dictationCleanup = .verbatim
        state.selectedDomains = [.aiVibeCoding, .softwareDevelopment]
        state.customDomainTerms = ["SayKuku", "Vibe Coding"]
        state.didCompleteOnboarding = true
        state.automaticAgentWriteBack = false

        let reloaded = environment.makeState()
        #expect(reloaded.recognitionLanguage == .english)
        #expect(reloaded.dictationNumberFormat == .spoken)
        #expect(reloaded.dictationCleanup == .verbatim)
        #expect(reloaded.selectedDomains == [.aiVibeCoding, .softwareDevelopment])
        #expect(reloaded.customDomainTerms == ["SayKuku", "Vibe Coding"])
        #expect(reloaded.didCompleteOnboarding)
        #expect(!reloaded.automaticAgentWriteBack)
    }

    @Test("menu bar-only close preference persists and keeps a recovery entry")
    @MainActor
    func menuBarOnlyClosePreference() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }

        let state = environment.makeState()
        #expect(!state.hideDockIconAfterMainWindowCloses)
        state.setShowInMenuBar(false)
        #expect(!state.showInMenuBar)

        state.hideDockIconAfterMainWindowCloses = true
        #expect(state.showInMenuBar)
        state.setShowInMenuBar(false)
        #expect(state.showInMenuBar)

        let reloaded = environment.makeState()
        #expect(reloaded.hideDockIconAfterMainWindowCloses)
        #expect(reloaded.showInMenuBar)

        reloaded.hideDockIconAfterMainWindowCloses = false
        reloaded.setShowInMenuBar(false)
        #expect(!reloaded.showInMenuBar)
    }

    @Test("snapshot persists and reloads")
    func persistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root)
        let entry = HistoryEntry(
            mode: .dictation, app: "Tests", createdAt: Date(timeIntervalSince1970: 1_700_000_000.123),
            durationSeconds: 1, input: "hello", output: "",
            status: .failed, errorMessage: "timeout"
        )
        try await store.replace(.init(history: [entry]))
        let reloaded = LocalStore(root: root)
        let snapshot = try await reloaded.load()
        #expect(snapshot.history == [entry])
        let storedBytes = try Data(contentsOf: root.appendingPathComponent("store.json"))
        #expect(String(decoding: storedBytes, as: UTF8.self).contains("hello"))
        let fileMode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("store.json").path)[.posixPermissions] as? NSNumber
        #expect(fileMode?.intValue == 0o600)
    }

    @Test("a malformed snapshot is backed up intact and never overwritten")
    func unreadableSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let snapshotURL = root.appendingPathComponent("store.json")
        let original = Data("not valid JSON".utf8)
        try original.write(to: snapshotURL)
        let store = LocalStore(root: root)

        guard case .movedAside(let backup)? = store.dataIssue else {
            Issue.record("Expected the malformed snapshot to be moved aside")
            return
        }
        #expect(backup.deletingLastPathComponent().path == root.path)
        #expect(backup.lastPathComponent.hasPrefix("store.corrupt-"))
        #expect(backup.pathExtension == "json")
        #expect(try Data(contentsOf: backup) == original)
        #expect(!FileManager.default.fileExists(atPath: snapshotURL.path))
        #expect(try await store.load().history.isEmpty)

        let entry = HistoryEntry(mode: .dictation, app: "Tests", durationSeconds: 1, input: "hello", output: "hello")
        try await store.replace(.init(history: [entry]))
        _ = try await store.saveAudio(Data("audio".utf8), id: entry.id)
        #expect(try Data(contentsOf: backup) == original)

        let reloaded = LocalStore(root: root)
        #expect(reloaded.dataIssue == nil)
        #expect(try await reloaded.load().history.map(\.id) == [entry.id])
    }

    @Test("unreadable records are skipped after the original is backed up")
    func tolerantSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let snapshotURL = root.appendingPathComponent("store.json")
        let readableID = UUID()
        let json = """
        {
          "history": [
            {
              "id": "\(readableID.uuidString)",
              "mode": "dictation",
              "app": "Tests",
              "createdAt": 1700000000123,
              "durationSeconds": 1,
              "input": "kept",
              "output": "kept",
              "isStarred": true
            },
            {
              "id": "\(UUID().uuidString)",
              "mode": "dictation",
              "app": "Tests",
              "createdAt": 1700000000456,
              "durationSeconds": 1,
              "input": "future",
              "output": "future",
              "isStarred": false,
              "status": "archivedInAFutureVersion"
            }
          ]
        }
        """
        let original = Data(json.utf8)
        try original.write(to: snapshotURL)
        let store = LocalStore(root: root)

        guard case .skippedRecords(let count, let backup)? = store.dataIssue else {
            Issue.record("Expected one skipped record")
            return
        }
        #expect(count == 1)
        #expect(backup.lastPathComponent.hasPrefix("store.corrupt-"))
        #expect(try Data(contentsOf: backup) == original)
        #expect(try Data(contentsOf: snapshotURL) == original)
        let snapshot = try await store.load()
        #expect(snapshot.history.map(\.id) == [readableID])
        #expect(snapshot.history.first?.isStarred == true)
        #expect(snapshot.entities.isEmpty)
    }

    @Test("legacy encrypted data is reported but left untouched")
    func legacyEncryptedData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioDirectory = root.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        #expect(await LocalStore(root: root).legacyEncryptedDataURL() == nil)

        let legacyAudio = audioDirectory.appendingPathComponent("\(UUID().uuidString).audio")
        try Data("encrypted-audio".utf8).write(to: legacyAudio)
        #expect(await LocalStore(root: root).legacyEncryptedDataURL()?.lastPathComponent == "Audio")

        let legacySnapshot = root.appendingPathComponent("store.data")
        let encrypted = Data("encrypted-snapshot".utf8)
        try encrypted.write(to: legacySnapshot)
        let store = LocalStore(root: root)
        #expect(await store.legacyEncryptedDataURL()?.lastPathComponent == "store.data")
        #expect(store.dataIssue == nil)
        #expect(try await store.load().history.isEmpty)
        #expect(try Data(contentsOf: legacySnapshot) == encrypted)
        #expect(FileManager.default.fileExists(atPath: legacyAudio.path))
    }

    @Test("history items can be starred and deleted with their recordings")
    @MainActor
    func historyManagement() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let store = LocalStore(root: environment.root)
        let state = environment.makeState(store: store)
        let recordedID = UUID()
        let filename = try await store.saveAudio(Data("audio".utf8), id: recordedID)
        let audioURL = environment.root.appendingPathComponent("Audio").appendingPathComponent(filename)
        let recorded = HistoryEntry(
            id: recordedID, mode: .dictation, app: "Notes", durationSeconds: 1,
            input: "hello", output: "hello", audioFilename: filename
        )
        let starred = HistoryEntry(mode: .agent, app: "Mail", durationSeconds: 1, input: "draft", output: "reply", isStarred: true)
        let plain = HistoryEntry(mode: .dictation, app: "Notes", durationSeconds: 1, input: "plain", output: "plain")
        state.historyEntries = [recorded, starred, plain]

        state.toggleHistoryStar(plain.id)
        #expect(state.historyEntries.first(where: { $0.id == plain.id })?.isStarred == true)
        state.toggleHistoryStar(plain.id)
        state.toggleHistoryStar(UUID())

        state.deleteHistoryEntry(recorded.id)
        #expect(state.historyEntries.map(\.id) == [starred.id, plain.id])
        #expect(await waitForRemoval(of: audioURL))

        state.clearHistory(keepingStarred: true)
        #expect(state.historyEntries.map(\.id) == [starred.id])
        state.clearHistory(keepingStarred: false)
        #expect(state.historyEntries.isEmpty)
    }

    @Test("legacy history without a status remains readable")
    func legacyHistoryStatus() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "mode": "dictation",
          "app": "Tests",
          "createdAt": 1700000000123,
          "durationSeconds": 1.25,
          "input": "hello",
          "output": "hello",
          "isStarred": false
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let entry = try decoder.decode(HistoryEntry.self, from: Data(json.utf8))

        #expect(entry.id == id)
        #expect(entry.status == .completed)
        #expect(entry.errorMessage == nil)
    }

    @Test("interrupted history is marked failed and keeps its audio")
    func interruptedHistoryRecovery() {
        let interrupted = HistoryEntry(
            mode: .dictation, app: "Notes", durationSeconds: 3, input: "", output: "",
            audioFilename: "a.wav", status: .processing
        )
        let completed = HistoryEntry(mode: .agent, app: "Mail", durationSeconds: 2, input: "a", output: "b")
        let recovered = AppState.recoveringInterruptedHistory([interrupted, completed], message: "SayKuku quit before this finished")

        #expect(recovered[0].status == .failed)
        #expect(recovered[0].errorMessage == "SayKuku quit before this finished")
        #expect(recovered[0].audioFilename == "a.wav")
        #expect(recovered[1] == completed)
    }

    @Test("audio is stored as a regular WAV file")
    func audioStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(root: root)
        let audio = Data("RIFF-private-audio-payload".utf8)
        let filename = try await store.saveAudio(audio, id: UUID())
        let stored = try Data(contentsOf: root.appendingPathComponent("Audio").appendingPathComponent(filename))
        #expect(filename.hasSuffix(".wav"))
        #expect(stored == audio)
        let fileMode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("Audio").appendingPathComponent(filename).path)[.posixPermissions] as? NSNumber
        #expect(fileMode?.intValue == 0o600)
        #expect(try await store.audio(named: filename) == audio)
        await #expect(throws: LocalStoreError.self) { try await store.audio(named: "../store.json") }
    }

    @Test("silence is rejected before transcription")
    func silenceDetection() {
        let silence = Data(repeating: 0, count: 16_000 * 2)
        #expect(!AudioCapture.containsSpeech(in: silence))

        var tone = Data()
        for index in 0..<(16_000 / 4) {
            var sample = Int16(sin(Double(index) * 2 * .pi * 440 / 16_000) * 4_000).littleEndian
            withUnsafeBytes(of: &sample) { tone.append(contentsOf: $0) }
        }
        #expect(AudioCapture.containsSpeech(in: tone))
    }
}
