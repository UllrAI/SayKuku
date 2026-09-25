import AppKit
import Testing
@testable import SayKuku

@Suite("App state")
struct AppStateTests {
    @Test("main navigation titles come from the string catalog")
    func navigationLocalization() {
        #expect(AppState.Destination.knowledge.title == localized("Memory"))
        #expect(AppState.Destination.allCases == [.home, .history, .knowledge])
        #expect(GlobalShortcutAction.voiceInput.title == localized("Voice Input"))
        #expect(HistoryMode.agent.title == localized("Voice Agent"))
    }

    @Test("every user-facing error describes itself")
    func errorDescriptions() {
        let errors: [any LocalizedError] = [
            QwenError.missingConfiguration, QwenError.invalidEndpoint, QwenError.invalidResponse, QwenError.noSpeech,
            QwenError.server(status: 400, message: ""), QwenError.server(status: 401, message: ""),
            QwenError.server(status: 403, message: ""), QwenError.server(status: 429, message: ""),
            QwenError.server(status: 500, message: ""), QwenError.protocolError(""), QwenError.timeout,
            QwenError.recordingTooLong,
            TextInteractionError.accessibilityRequired, TextInteractionError.noFocusedElement,
            TextInteractionError.sensitiveTarget, TextInteractionError.targetChanged, TextInteractionError.writeFailed,
            AudioCaptureError.microphoneUnavailable, AudioCaptureError.unsupportedFormat,
            AgentActionError.deleteNeedsInsert, AgentActionError.shortcutFailed, AgentActionError.shortcutTimedOut,
            LocalStoreError.unreadableSnapshot, LocalStoreError.invalidAudioFilename,
            SecureStorageError.keychain(-25300), SecureStorageError.invalidData
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false, "\(error) has no description")
        }
    }

    @Test("the interface language maps to and from AppleLanguages")
    func appLanguageOverride() {
        #expect(AppLanguage(appleLanguages: nil) == .system)
        #expect(AppLanguage(appleLanguages: ["zh-Hans-CN", "en"]) == .chinese)
        #expect(AppLanguage(appleLanguages: ["en-GB"]) == .english)
        // Set elsewhere, such as in System Settings, and not one of the choices.
        #expect(AppLanguage(appleLanguages: ["zh-Hant"]) == .system)
        for language in AppLanguage.allCases {
            #expect(AppLanguage(appleLanguages: language.appleLanguages) == language)
        }
    }

    @Test("settings saved by earlier builds are migrated once")
    @MainActor
    func legacySettings() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        environment.defaults.set("单击 Fn", forKey: "inputMode")
        // Unmapped, so the migration only deletes the key and never writes the test runner's AppleLanguages.
        environment.defaults.set("unknown", forKey: "appLanguage")
        let state = environment.makeState()
        #expect(state.settings.inputMode == .tap)
        #expect(environment.defaults.string(forKey: "inputMode") == "tap")
        #expect(environment.defaults.object(forKey: "appLanguage") == nil)
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
        #expect(AppState.DictationPhase.idle.status(state) == nil)
        #expect(AppState.AgentPhase.answerReady.status(state) == nil)
        state.agentCommand = localized("Listening…")
        #expect(AppState.AgentPhase.processing.status(state) == localized("Running…"))
        let task = "Summarize this page"
        state.agentCommand = task
        #expect(AppState.AgentPhase.processing.status(state) == localized("Running · \(task)"))
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
        state.data.historyEntries = [old]
        state.settings.historyRetention = .off
        #expect(HistoryRetention.off.days == nil)
        #expect(HistoryRetention.allCases.first == .off)
        #expect(state.data.historyEntries == [old])
        #expect(environment.makeState().settings.historyRetention == .off)
    }

    @Test("sound cues default on and survive a relaunch")
    @MainActor
    func soundCuesSetting() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let state = environment.makeState()
        #expect(state.settings.soundCuesEnabled)
        state.settings.soundCuesEnabled = false
        #expect(!environment.makeState().settings.soundCuesEnabled)
    }

    @Test("the search engine follows the region until the user picks one, then stays put")
    @MainActor
    func searchEngineSetting() {
        let environment = AppStateTestEnvironment()
        defer { environment.clean() }
        let state = environment.makeState()
        state.settings.qwenRegion = .beijing
        #expect(state.settings.searchEngine == .bing)
        state.settings.qwenRegion = .singapore
        #expect(state.settings.searchEngine == .google)
        #expect(environment.defaults.string(forKey: "agent.searchEngine") == nil)
        #expect(environment.makeState().settings.searchEngine == .google)

        state.settings.searchEngine = .duckduckgo
        state.settings.qwenRegion = .beijing
        #expect(state.settings.searchEngine == .duckduckgo)
        #expect(environment.makeState().settings.searchEngine == .duckduckgo)
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
        await state.data.loadStoredData()

        #expect(Set(state.data.knowledgeEntities.map(\.name)) == ["SayKuku", "Vibe Coding", "MCP"])
        #expect(state.data.knowledgeEntities.first { $0.id == saved.id }?.type == .project)
        #expect(state.data.knowledgeEntities.filter { $0.id != saved.id }.allSatisfy { $0.type == .term && $0.source == .manual })
        #expect(environment.defaults.object(forKey: legacyKey) == nil)
        #expect(state.toast == nil)

        await state.data.flushPersistence()
        let reloaded = try await LocalStore(root: environment.root).load()
        #expect(reloaded.entities.count == 3)
    }

    @Test("toasts with the same copy are still distinct")
    func toastIdentity() {
        #expect(ToastMessage(text: "已复制", symbol: "doc.on.doc") != ToastMessage(text: "已复制", symbol: "doc.on.doc"))
    }
}
