import AppKit
import Testing
@testable import SayKuku

@Suite("App state")
struct AppStateTests {
    @Test("main navigation titles follow the selected language")
    @MainActor
    func navigationLocalization() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let state = environment.makeState()
        state.appLanguage = .chinese
        #expect(AppState.Destination.knowledge.title(state) == "知识")
        #expect(state.voiceInputTitle == "语音输入")
        #expect(state.voiceAgentTitle == "语音 Agent")
        state.appLanguage = .english
        #expect(AppState.Destination.knowledge.title(state) == "Knowledge")
        #expect(state.voiceInputTitle == "Voice Input")
        #expect(state.voiceAgentTitle == "Voice Agent")
    }

    @Test("failed or cancelled dictation with a recording can be transcribed again")
    func retryableHistory() {
        func entry(_ mode: HistoryMode, _ status: HistoryStatus, audio: String? = "clip.wav") -> HistoryEntry {
            HistoryEntry(mode: mode, app: "Notes", durationSeconds: 1, input: "", output: "", audioFilename: audio, status: status)
        }
        #expect(entry(.dictation, .cancelled).canRetryTranscription)
        #expect(entry(.dictation, .failed).canRetryTranscription)
        #expect(!entry(.dictation, .cancelled, audio: nil).canRetryTranscription)
        #expect(!entry(.dictation, .completed).canRetryTranscription)
        #expect(!entry(.dictation, .processing).canRetryTranscription)
        #expect(!entry(.agent, .cancelled).canRetryTranscription)
    }

    @Test("overlay status names the running task, never the listening placeholder")
    @MainActor
    func overlayPhaseStatus() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let state = environment.makeState()
        state.appLanguage = .english
        #expect(AppState.DictationPhase.idle.status(state) == nil)
        #expect(AppState.AgentPhase.answerReady.status(state) == nil)
        state.agentCommand = "Listening…"
        #expect(AppState.AgentPhase.processing.status(state) == "Running…")
        state.agentCommand = "Summarize this page"
        #expect(AppState.AgentPhase.processing.status(state) == "Running · Summarize this page")
    }

    @Test("Don’t keep never expires existing history and survives a relaunch")
    @MainActor
    func historyRetentionOff() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let state = environment.makeState()
        let old = HistoryEntry(
            mode: .dictation, app: "Notes", createdAt: .now.addingTimeInterval(-400 * 86_400),
            durationSeconds: 1, input: "hello", output: "hello"
        )
        state.historyEntries = [old]
        state.historyRetention = .off
        #expect(HistoryRetention.off.days == nil)
        #expect(HistoryRetention.allCases.first == .off)
        #expect(state.historyEntries == [old])
        #expect(environment.makeState().historyRetention == .off)
    }

    @Test("sound cues default on and survive a relaunch")
    @MainActor
    func soundCuesSetting() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let state = environment.makeState()
        #expect(state.soundCuesEnabled)
        state.soundCuesEnabled = false
        #expect(!environment.makeState().soundCuesEnabled)
    }

    @Test("the search engine follows the region until the user picks one, then stays put")
    @MainActor
    func searchEngineSetting() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let state = environment.makeState()
        state.qwenRegion = .beijing
        #expect(state.searchEngine == .bing)
        state.qwenRegion = .singapore
        #expect(state.searchEngine == .google)
        #expect(environment.defaults.string(forKey: "agent.searchEngine") == nil)
        #expect(environment.makeState().searchEngine == .google)

        state.searchEngine = .duckduckgo
        state.qwenRegion = .beijing
        #expect(state.searchEngine == .duckduckgo)
        #expect(environment.makeState().searchEngine == .duckduckgo)
    }

    @Test("only the listening phase counts as recording, so cancels elsewhere stay silent")
    @MainActor
    func recordingPhases() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let state = environment.makeState()
        #expect(!state.isRecording)
        state.dictationPhase = .listening
        #expect(state.isRecording)
        state.dictationPhase = .processing
        #expect(!state.isRecording)
        state.agentPhase = .listening
        #expect(state.isRecording)
        state.agentPhase = .transcribing
        #expect(!state.isRecording)
    }

    @Test("each sound cue is bundled, loads, and stays short")
    @MainActor
    func soundCueClips() throws {
        for cue in SoundCues.Cue.allCases {
            let url = try #require(cue.url)
            let sound = try #require(NSSound(contentsOf: url, byReference: true))
            #expect(sound.duration > 0 && sound.duration <= 0.15)
        }
    }

    @Test("custom words from earlier builds move into Knowledge once it loads")
    @MainActor
    func legacyCustomTermsMigration() async throws {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let legacyKey = "dictation.customDomainTerms"
        let saved = KnowledgeEntity(name: "SayKuku", type: .project)
        try await LocalStore(root: environment.root).replace(.init(entities: [saved]))
        environment.defaults.set(["Vibe Coding", "saykuku", "MCP"], forKey: legacyKey)

        let state = environment.makeState(persistenceDelay: .seconds(60))
        await state.loadStoredData()

        #expect(Set(state.knowledgeEntities.map(\.name)) == ["SayKuku", "Vibe Coding", "MCP"])
        #expect(state.knowledgeEntities.first { $0.id == saved.id }?.type == .project)
        #expect(state.knowledgeEntities.filter { $0.id != saved.id }.allSatisfy { $0.type == .term && $0.source == .manual })
        #expect(environment.defaults.object(forKey: legacyKey) == nil)
        #expect(state.toast == nil)

        await state.flushPersistence()
        let reloaded = try await LocalStore(root: environment.root).load()
        #expect(reloaded.entities.count == 3)
    }

    @Test("toasts with the same copy are still distinct")
    func toastIdentity() {
        #expect(ToastMessage(text: "已复制", symbol: "doc.on.doc") != ToastMessage(text: "已复制", symbol: "doc.on.doc"))
    }
}
