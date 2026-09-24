import Foundation
import Testing
@testable import SayKuku

@Suite("Qwen settings")
struct QwenSettingsTests {
    @Test("API Key draft state compares the trimmed draft with the saved key")
    func apiKeyDraftState() {
        #expect(APIKeyDraftState(draft: "", saved: "") == .empty)
        #expect(APIKeyDraftState(draft: "  ", saved: "") == .empty)
        #expect(APIKeyDraftState(draft: "sk-1", saved: "sk-1") == .saved)
        #expect(APIKeyDraftState(draft: " sk-1\n", saved: "sk-1") == .saved)
        #expect(APIKeyDraftState(draft: "sk-2", saved: "sk-1") == .modified)
        #expect(APIKeyDraftState(draft: "sk-1", saved: "") == .modified)
        #expect(APIKeyDraftState(draft: "", saved: "sk-1") == .cleared)
        #expect(!APIKeyDraftState(draft: "sk-1", saved: "sk-1").hasChanges)
        #expect(APIKeyDraftState(draft: "", saved: "sk-1").hasChanges)
    }

    @Test("stored models fall back only when missing or retired")
    func storedModels() {
        let realtime = QwenModelCatalog.defaultRealtimeModel
        #expect(QwenModelCatalog.realtimeModel(stored: nil) == realtime)
        #expect(QwenModelCatalog.realtimeModel(stored: "  ") == realtime)
        #expect(QwenModelCatalog.realtimeModel(stored: "qwen3.8-omni-flash-realtime") == realtime)
        #expect(QwenModelCatalog.realtimeModel(stored: "qwen3-asr-flash-realtime-2025-10-27") == realtime)
        #expect(QwenModelCatalog.realtimeModel(stored: "my-realtime-model") == "my-realtime-model")
        #expect(QwenModelCatalog.reasoningModel(stored: nil) == QwenModelCatalog.defaultReasoningModel)
        #expect(QwenModelCatalog.reasoningModel(stored: " qwen-custom ") == "qwen-custom")
    }

    @Test("model options keep the current value visible without dated presets")
    func modelOptions() {
        let presets = QwenModelCatalog.reasoningModels
        #expect(QwenModelCatalog.options(presets, including: presets[0]) == presets)
        #expect(QwenModelCatalog.options(presets, including: "qwen-custom") == presets + ["qwen-custom"])
        #expect(QwenModelCatalog.options(presets, including: "") == presets)

        let datedSnapshot = #/\d{4}-\d{2}-\d{2}$/#
        for model in QwenModelCatalog.realtimeModels + QwenModelCatalog.reasoningModels {
            #expect(model.firstMatch(of: datedSnapshot) == nil)
        }
    }

    @Test("region titles follow the interface language")
    func regionTitles() {
        #expect(QwenRegion.beijing.title(isChineseUI: true) == "北京")
        #expect(QwenRegion.singapore.title(isChineseUI: true) == "新加坡")
        #expect(QwenRegion.beijing.title(isChineseUI: false) == "China (Beijing)")
        #expect(QwenRegion.singapore.title(isChineseUI: false) == "International (Singapore)")
    }

    @Test("saved API Key persists in the Keychain and clearing it removes the key")
    @MainActor
    func apiKeyPersistence() throws {
        let environment = QwenSettingsTestEnvironment()
        defer { environment.clean() }

        let state = environment.makeState()
        try state.saveAPIKey("  sk-test \n")
        #expect(state.apiKey == "sk-test")
        #expect(try environment.keychain.string(for: "qwen.apiKey") == "sk-test")
        #expect(environment.makeState().apiKey == "sk-test")

        try state.saveAPIKey("")
        #expect(state.apiKey.isEmpty)
        #expect(try environment.keychain.string(for: "qwen.apiKey") == nil)
    }

    @Test("retired stored models migrate while custom models survive reloads")
    @MainActor
    func modelMigration() {
        let environment = QwenSettingsTestEnvironment()
        defer { environment.clean() }

        environment.defaults.set("qwen3-asr-flash-realtime", forKey: "qwen.realtimeModel")
        environment.defaults.set("qwen-custom-agent", forKey: "qwen.reasoningModel")
        let state = environment.makeState()
        #expect(state.realtimeModel == QwenModelCatalog.defaultRealtimeModel)
        #expect(state.reasoningModel == "qwen-custom-agent")

        state.realtimeModel = "qwen-custom-realtime"
        #expect(environment.makeState().realtimeModel == "qwen-custom-realtime")
    }

    @Test("connection-affecting edits reset the test result")
    @MainActor
    func connectionStateResets() {
        let environment = QwenSettingsTestEnvironment()
        defer { environment.clean() }

        let state = environment.makeState()
        let edits: [@MainActor (AppState) -> Void] = [
            { $0.qwenRegion = .singapore },
            { $0.qwenWorkspaceID = "ws-1" },
            { $0.realtimeModel = "qwen-custom-realtime" },
            { $0.reasoningModel = "qwen-custom-agent" }
        ]
        for edit in edits {
            state.connectionState = .connected(realtimeMilliseconds: 120, chatMilliseconds: 340)
            edit(state)
            #expect(state.connectionState == .idle)
        }
    }
}

@MainActor
private struct QwenSettingsTestEnvironment {
    let suite: String
    let defaults: UserDefaults
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let keychain = KeychainStore(service: "com.saykuku.tests.\(UUID().uuidString)")

    init() {
        let suite = "SayKukuTests.\(UUID().uuidString)"
        self.suite = suite
        defaults = UserDefaults(suiteName: suite)!
    }

    func makeState() -> AppState {
        AppState(defaults: defaults, store: LocalStore(root: root), keychain: keychain)
    }

    func clean() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
        try? keychain.remove("qwen.apiKey")
    }
}
