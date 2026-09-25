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

    @Test("toasts with the same copy are still distinct")
    func toastIdentity() {
        #expect(ToastMessage(text: "已复制", symbol: "doc.on.doc") != ToastMessage(text: "已复制", symbol: "doc.on.doc"))
    }
}
