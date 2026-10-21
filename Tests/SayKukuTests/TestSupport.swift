import Foundation
import os
import Testing
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
    static func fake(
        selectedText: String = "", valueBefore: String? = nil, selectedRange: CFRange? = nil,
        isSensitive: Bool = false, hasDictationTarget: Bool = true,
        bundleID: String = "com.example.editor"
    ) -> TextTargetSnapshot {
        TextTargetSnapshot(
            appPID: 0,
            bundleID: bundleID,
            appName: "Editor",
            windowTitle: "",
            hasDictationTarget: hasDictationTarget,
            windowElement: nil,
            textElement: nil,
            selectionElement: nil,
            selectedRange: selectedRange,
            selectedText: selectedText,
            valueBefore: valueBefore,
            isSensitive: isSensitive,
            caretFrame: nil
        )
    }
}

/// Starts at once, or fails with `startError`, and hands back `recording` when stopped.
final class FakeAudioCapturing: AudioCapturing {
    let recording: AudioCapture.Recording
    let startError: (any Error)?
    let startDelay: Duration
    private let starts = OSAllocatedUnfairLock(initialState: 0)

    var startCount: Int { starts.withLock { $0 } }

    init(
        recording: AudioCapture.Recording = .speech,
        startError: (any Error)? = nil,
        startDelay: Duration = .zero
    ) {
        self.recording = recording
        self.startError = startError
        self.startDelay = startDelay
    }

    func start(
        onLevel: @escaping @Sendable (Double) -> Void,
        onChunk: @escaping @Sendable (Data) -> Void,
        onInterruption: @escaping @Sendable () -> Void
    ) -> Task<Void, Error> {
        starts.withLock { $0 += 1 }
        // One chunk, so a streamed dictation has audio to send.
        onChunk(Data(count: 2))
        let startError = startError
        let startDelay = startDelay
        return Task {
            if startDelay > .zero { try await Task.sleep(for: startDelay) }
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
    private var speechStoppedHandler: (@Sendable () -> Void)?
    private(set) var targetApps: [String?] = []
    private(set) var cursorContexts: [DictationCursorContext?] = []
    private(set) var formats: [(DictationNumberFormat, DictationCleanup, Bool, String)] = []
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
        keepEndingPunctuation: Bool,
        expressionPreference: String,
        cursorContext: DictationCursorContext?,
        memoryPrompt: String
    ) async throws {
        targetApps.append(targetApp)
        cursorContexts.append(cursorContext)
        formats.append((numberFormat, cleanup, keepEndingPunctuation, expressionPreference))
        speechStoppedHandler = onSpeechStopped
    }

    func reportSpeechStopped() { speechStoppedHandler?() }

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

/// Batch transcription and refinement each take the next queued reply, repeating the last one;
/// the Agent always gets `agentReply`.
final class FakeReasoning: Reasoning {
    enum Transcription: Sendable {
        case text(String)
        case failure(QwenError)
        /// Waits until the caller is cancelled, then returns the text anyway, like a reply that lands too late.
        case lateText(String)
    }

    enum Refinement: Sendable {
        /// Replies with the transcript it was sent.
        case echo
        case text(String)
        case failure(QwenError)
        /// Waits until the caller is cancelled, then returns the text anyway.
        case lateText(String)
    }

    private struct State {
        var transcriptions: [Transcription]
        var refinements: [Refinement]
        var transcribeCount = 0
        var refineCount = 0
        var refineCancelled = false
        var refinementInstructions: [String] = []
        var refinementMessages: [String] = []
        var targetApps: [String?] = []
        var cursorContexts: [DictationCursorContext?] = []
        var formats: [(DictationNumberFormat, DictationCleanup, Bool, String)] = []
        var agentContexts: [[ContextItem]] = []
        var agentMemoryPrompts: [String] = []
    }

    private let state: OSAllocatedUnfairLock<State>
    private let agentReply: Result<AgentResponse, QwenError>

    init(
        transcriptions: [Transcription] = [.text("Hello world.")],
        refinements: [Refinement] = [.echo],
        agentReply: Result<AgentResponse, QwenError> = .failure(.invalidResponse)
    ) {
        precondition(!transcriptions.isEmpty && !refinements.isEmpty)
        state = OSAllocatedUnfairLock(initialState: State(transcriptions: transcriptions, refinements: refinements))
        self.agentReply = agentReply
    }

    var transcribeCount: Int { state.withLock { $0.transcribeCount } }
    var refineCount: Int { state.withLock { $0.refineCount } }
    /// Whether a late refinement saw its caller cancelled.
    var refineCancelled: Bool { state.withLock { $0.refineCancelled } }
    var refinementInstructions: [String] { state.withLock { $0.refinementInstructions } }
    var refinementMessages: [String] { state.withLock { $0.refinementMessages } }
    var targetApps: [String?] { state.withLock { $0.targetApps } }
    var cursorContexts: [DictationCursorContext?] { state.withLock { $0.cursorContexts } }
    var formats: [(DictationNumberFormat, DictationCleanup, Bool, String)] { state.withLock { $0.formats } }
    var agentContexts: [[ContextItem]] { state.withLock { $0.agentContexts } }
    var agentMemoryPrompts: [String] { state.withLock { $0.agentMemoryPrompts } }

    func transcribeAudio(
        apiKey: String,
        configuration: QwenConfiguration,
        wav: Data,
        recognitionLanguage: RecognitionLanguage,
        numberFormat: DictationNumberFormat,
        cleanup: DictationCleanup,
        targetApp: String?,
        keepEndingPunctuation: Bool,
        expressionPreference: String,
        cursorContext: DictationCursorContext?,
        memoryPrompt: String
    ) async throws -> String {
        let reply = state.withLock { current in
            current.transcribeCount += 1
            current.targetApps.append(targetApp)
            current.cursorContexts.append(cursorContext)
            current.formats.append((numberFormat, cleanup, keepEndingPunctuation, expressionPreference))
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
        memoryPrompt: String
    ) async throws -> AgentResponse {
        state.withLock {
            $0.agentContexts.append(context)
            $0.agentMemoryPrompts.append(memoryPrompt)
        }
        return try agentReply.get()
    }

    func refineDictation(
        apiKey: String, configuration: QwenConfiguration, instructions: String, userMessage: String
    ) async throws -> String {
        let reply = state.withLock { current in
            current.refineCount += 1
            current.refinementInstructions.append(instructions)
            current.refinementMessages.append(userMessage)
            return current.refinements.count > 1 ? current.refinements.removeFirst() : current.refinements[0]
        }
        switch reply {
        case .echo:
            // The transcript sits between the opening and closing tag lines.
            return userMessage.split(separator: "\n", omittingEmptySubsequences: false)
                .dropFirst().dropLast().joined(separator: "\n")
        case .text(let text):
            return text
        case .failure(let error):
            throw error
        case .lateText(let text):
            try? await Task.sleep(for: .seconds(60))
            if Task.isCancelled { state.withLock { $0.refineCancelled = true } }
            return text
        }
    }

    func extractMemory(apiKey: String, configuration: QwenConfiguration, text: String) async throws -> [ProposedEntity] {
        []
    }

    func testConnection(apiKey: String, configuration: QwenConfiguration) async throws -> Duration {
        .zero
    }
}

/// Captures `snapshot`, shows `screenText` as the window's text, and records every write attempt;
/// set an error to make that step fail.
@MainActor
final class FakeTextWriting: TextWriting {
    var snapshot: TextTargetSnapshot
    var captureError: TextInteractionError?
    var writeOutcome = TextWriteOutcome.verified
    var writeError: TextInteractionError?
    var replacementError: TextInteractionError?
    /// What `currentValue(of:)` reads back from the field.
    var fieldValue: String?
    var screenText = ""
    var afterSafeTarget: (() -> Void)?
    private(set) var writes: [String] = []
    private(set) var visibleTextReads = 0

    init(snapshot: TextTargetSnapshot = .fake()) {
        self.snapshot = snapshot
    }

    func captureTarget(
        requiringWindow: Bool, includingCaretFrame: Bool, onSafeTarget: () -> Void
    ) throws -> TextTargetSnapshot {
        if let captureError { throw captureError }
        if snapshot.isSensitive { throw TextInteractionError.sensitiveTarget }
        onSafeTarget()
        afterSafeTarget?()
        return snapshot
    }

    func write(_ text: String, to snapshot: TextTargetSnapshot) async throws -> TextWriteOutcome {
        writes.append(text)
        if let writeError { throw writeError }
        return writeOutcome
    }

    func currentValue(of snapshot: TextTargetSnapshot) -> String? { fieldValue }

    func browserPageAddress(in snapshot: TextTargetSnapshot) -> String? { nil }

    func visibleText(in snapshot: TextTargetSnapshot) -> String {
        visibleTextReads += 1
        return screenText
    }

    func replacementSnapshot(for write: VerifiedWrite) throws -> TextTargetSnapshot {
        if let replacementError { throw replacementError }
        // Like the real one: the written text, selected in the field it was written to.
        return .fake(
            selectedText: write.text,
            valueBefore: write.expectedValue,
            selectedRange: CFRange(location: write.target.selectedRange?.location ?? 0, length: (write.text as NSString).length)
        )
    }
}

/// What a live dictation eval needs: the fixture recordings `Scripts/eval-dictation.sh <suite>` wrote to
/// `Build/<audio folder>`, and the Qwen account to send them to.
struct LiveDictationEval {
    let apiKey: String
    let configuration: QwenConfiguration
    private let suite: String
    private let audioDirectory: URL

    /// Nil unless `SAYKUKU_LIVE_QWEN_TEST=1`, so a default `swift test` reaches neither the network nor the
    /// Keychain. The region and Workspace ID come from `SAYKUKU_TEST_REGION` and `SAYKUKU_TEST_WORKSPACE_ID`.
    init?(suite: String, audioFolder: String) throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SAYKUKU_LIVE_QWEN_TEST"] == "1" else { return nil }
        apiKey = try #require(try KeychainStore().string(for: "qwen.apiKey"))
        configuration = QwenConfiguration(
            region: environment["SAYKUKU_TEST_REGION"].flatMap(QwenRegion.init(rawValue:)) ?? .beijing,
            workspaceID: environment["SAYKUKU_TEST_WORKSPACE_ID"] ?? "",
            realtimeModel: QwenModelCatalog.defaultRealtimeModel,
            reasoningModel: QwenModelCatalog.defaultReasoningModel
        )
        self.suite = suite
        audioDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Build/\(audioFolder)")
    }

    /// `NN.wav` for zero-based sample `index`, after `NN.txt` confirms it was spoken from `spoken`.
    func recording(at index: Int, spoken: String) throws -> (name: String, wav: Data) {
        let name = String(format: "%02d", index + 1)
        let recorded = try String(contentsOf: audioDirectory.appendingPathComponent("\(name).txt"), encoding: .utf8)
        try #require(recorded == spoken, "\(name).wav is out of date; run Scripts/eval-dictation.sh \(suite)")
        return (name, try Data(contentsOf: audioDirectory.appendingPathComponent("\(name).wav")))
    }
}
