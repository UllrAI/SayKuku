import Foundation
import Synchronization
@testable import SayKuku

/// Isolated defaults, storage folder, and Keychain service for building `AppState` in tests.
@MainActor
struct AppStateTestEnvironment {
    let suite: String
    let defaults: UserDefaults
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let keychain = KeychainStore(service: "com.saykuku.tests.\(UUID().uuidString)")

    init() {
        let suite = "SayKukuTests.\(UUID().uuidString)"
        self.suite = suite
        defaults = UserDefaults(suiteName: suite)!
    }

    /// A new state reads whatever earlier states in this environment saved.
    func makeState(
        store: LocalStore? = nil,
        persistenceDelay: Duration = .milliseconds(500),
        dependencies: AppState.Dependencies = .live
    ) -> AppState {
        AppState(
            defaults: defaults, store: store ?? LocalStore(root: root),
            keychain: keychain, persistenceDelay: persistenceDelay, dependencies: dependencies
        )
    }

    func clean() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
        try? keychain.remove("qwen.apiKey")
    }
}

extension AppState.Dependencies {
    /// Fakes throughout, with the microphone reported as allowed.
    @MainActor static func fake(
        audio: FakeAudioCapturing = FakeAudioCapturing(),
        realtime: FakeRealtime = FakeRealtime(),
        reasoning: FakeReasoning = FakeReasoning(),
        text: FakeTextWriting = FakeTextWriting()
    ) -> AppState.Dependencies {
        AppState.Dependencies(
            audioCapture: audio,
            realtimeClient: realtime,
            reasoningClient: reasoning,
            textInteraction: text,
            systemPermissions: SystemPermissionController(microphoneStatus: { .authorized })
        )
    }
}

extension AudioCapture.Recording {
    /// Empty WAV data, so nothing is written to the History audio folder.
    static let speech = AudioCapture.Recording(wav: Data(), duration: 1, hasSpeech: true)
    static let silence = AudioCapture.Recording(wav: Data(), duration: 1, hasSpeech: false)
}

extension TextTargetSnapshot {
    /// A plain, non-sensitive field with no Accessibility elements behind it.
    static func fake(selectedText: String = "") -> TextTargetSnapshot {
        TextTargetSnapshot(
            appPID: 0,
            bundleID: "com.example.editor",
            appName: "Editor",
            windowTitle: "",
            windowElement: nil,
            textElement: nil,
            selectedRange: nil,
            selectedText: selectedText,
            valueBefore: nil,
            isSensitive: false,
            caretFrame: nil
        )
    }
}

/// Starts at once, or fails with `startError`, and hands back `recording` when stopped.
final class FakeAudioCapturing: AudioCapturing {
    let recording: AudioCapture.Recording
    let startError: (any Error)?

    init(recording: AudioCapture.Recording = .speech, startError: (any Error)? = nil) {
        self.recording = recording
        self.startError = startError
    }

    func start(
        onLevel: @escaping @Sendable (Double) -> Void,
        onChunk: @escaping @Sendable (Data) -> Void,
        onInterruption: @escaping @Sendable () -> Void
    ) -> Task<Void, Error> {
        // One chunk, so a streamed dictation has audio to send.
        onChunk(Data(count: 2))
        let startError = startError
        return Task {
            if let startError { throw startError }
        }
    }

    func stop() -> AudioCapture.Recording { recording }

    func cancel() {}
}

/// Connects at once and either returns `transcript` on commit or throws `commitError`.
actor FakeRealtime: RealtimeTranscribing {
    private let transcript: String
    private let commitError: QwenError?
    private(set) var targetApps: [String?] = []
    private(set) var appendCount = 0
    private(set) var commitCount = 0

    init(transcript: String = "", commitError: QwenError? = nil) {
        self.transcript = transcript
        self.commitError = commitError
    }

    func connect(
        session: UUID,
        apiKey: String,
        configuration: QwenConfiguration,
        autoStop: Bool,
        onSpeechStopped: @escaping @Sendable () -> Void,
        onDelta: @escaping @Sendable (String) -> Void,
        recognitionLanguage: RecognitionLanguage,
        numberFormat: DictationNumberFormat,
        cleanup: DictationCleanup,
        targetApp: String?,
        knowledgePrompt: String
    ) async throws {
        targetApps.append(targetApp)
    }

    func append(_ pcm16: Data, session: UUID) async throws {
        appendCount += 1
    }

    func commit(session: UUID, timeout: Duration) async throws -> String {
        commitCount += 1
        if let commitError { throw commitError }
        return transcript
    }

    func cancel(session: UUID) {}
}

/// Batch transcription takes the next queued reply, repeating the last one; the Agent always gets `agentReply`.
final class FakeReasoning: Reasoning {
    enum Transcription: Sendable {
        case text(String)
        case failure(QwenError)
        /// Waits until the caller is cancelled, then returns the text anyway, like a reply that lands too late.
        case lateText(String)
    }

    private struct State {
        var transcriptions: [Transcription]
        var transcribeCount = 0
        var targetApps: [String?] = []
    }

    private let state: Mutex<State>
    private let agentReply: Result<AgentResponse, QwenError>

    init(
        transcriptions: [Transcription] = [.text("Hello world.")],
        agentReply: Result<AgentResponse, QwenError> = .failure(.invalidResponse)
    ) {
        precondition(!transcriptions.isEmpty)
        state = Mutex(State(transcriptions: transcriptions))
        self.agentReply = agentReply
    }

    var transcribeCount: Int { state.withLock { $0.transcribeCount } }
    var targetApps: [String?] { state.withLock { $0.targetApps } }

    func transcribeAudio(
        apiKey: String,
        configuration: QwenConfiguration,
        wav: Data,
        recognitionLanguage: RecognitionLanguage,
        numberFormat: DictationNumberFormat,
        cleanup: DictationCleanup,
        targetApp: String?,
        knowledgePrompt: String
    ) async throws -> String {
        let reply = state.withLock { current in
            current.transcribeCount += 1
            current.targetApps.append(targetApp)
            return current.transcriptions.count > 1 ? current.transcriptions.removeFirst() : current.transcriptions[0]
        }
        switch reply {
        case .text(let text):
            return text
        case .failure(let error):
            throw error
        case .lateText(let text):
            try? await Task.sleep(for: .seconds(60))
            return text
        }
    }

    func respondToAudio(
        apiKey: String,
        configuration: QwenConfiguration,
        wav: Data,
        context: [ContextItem],
        sessions: [AgentSession],
        textField: AgentTextField,
        matchAppTone: Bool,
        knowledgePrompt: String
    ) async throws -> AgentResponse {
        try agentReply.get()
    }

    func extractKnowledge(apiKey: String, configuration: QwenConfiguration, text: String) async throws -> [ProposedEntity] {
        []
    }

    func testConnection(apiKey: String, configuration: QwenConfiguration) async throws -> Duration {
        .zero
    }
}

/// Captures `snapshot` and records every write attempt; set an error to make that step fail.
@MainActor
final class FakeTextWriting: TextWriting {
    var snapshot: TextTargetSnapshot
    var writeOutcome = TextWriteOutcome.verified
    var writeError: TextInteractionError?
    var replacementError: TextInteractionError?
    private(set) var writes: [String] = []

    init(snapshot: TextTargetSnapshot = .fake()) {
        self.snapshot = snapshot
    }

    func captureTarget(requiringWindow: Bool, includingCaretFrame: Bool) throws -> TextTargetSnapshot {
        snapshot
    }

    func write(_ text: String, to snapshot: TextTargetSnapshot) async throws -> TextWriteOutcome {
        writes.append(text)
        if let writeError { throw writeError }
        return writeOutcome
    }

    func currentValue(of snapshot: TextTargetSnapshot) -> String? { nil }

    func browserPageAddress(in snapshot: TextTargetSnapshot) -> String? { nil }

    func replacementSnapshot(for write: VerifiedWrite) throws -> TextTargetSnapshot {
        if let replacementError { throw replacementError }
        return write.target
    }
}
