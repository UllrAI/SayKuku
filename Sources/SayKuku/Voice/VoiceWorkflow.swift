import AppKit
import Observation
import os
import SwiftUI

private struct PendingExternalAction {
    let response: AgentResponse
    let historyID: UUID?
    let session: AgentSession?
}

/// Voice Input and Voice Agent: recording, transcription, the Agent's actions, writing into the focused
/// app, and the overlay that shows them. What only the main window can do goes through the handlers,
/// which `AppState` sets.
@MainActor
@Observable
final class VoiceWorkflow {
    enum AnalyticsEvent { case voiceInput, voiceAgent }
    enum DictationPhase: Equatable {
        case idle, starting, listening, processing, success, copyReady

        /// Recording or waiting on the model. Finished states close on their own or from their card.
        var isCancellable: Bool { self == .starting || self == .listening || self == .processing }
    }

    enum AgentPhase: Equatable {
        case hidden, starting, listening, transcribing, processing, result, copyReady, answerReady

        /// Recording or waiting on the model. Finished states close on their own or from their card.
        var isCancellable: Bool { self == .starting || self == .listening || self == .transcribing || self == .processing }
    }

    var dictationPhase: DictationPhase = .idle { didSet { overlayController?.refresh() } }
    var agentPhase: AgentPhase = .hidden { didSet { overlayController?.refresh() } }
    /// True while the microphone is capturing for either workflow.
    var isRecording: Bool { dictationPhase == .listening || agentPhase == .listening }
    /// Also true while the microphone is still starting, so a release, second press or Esc
    /// in that window can stop the start instead of going unheard.
    var dictationIsListening: Bool { dictationPhase == .starting || dictationPhase == .listening || startingWorkflow == .dictation }
    var agentIsListening: Bool { agentPhase == .starting || agentPhase == .listening || startingWorkflow == .agent }
    var canPromoteFnTap: Bool { fnTapDictation && dictationIsListening }
    var contextItems: [ContextItem] = []
    var agentCommand = ""
    var liveTranscript = ""
    var inputLevel = 0.0
    var pendingCopyText = "" { didSet { hasCopiedPendingText = false } }
    /// Whether `pendingCopyText` is on the pasteboard, so the copy fallback can say so.
    private(set) var hasCopiedPendingText = false
    var pendingAnswerText = ""
    /// Measured from `pendingAnswerText` before the answer card shows.
    private(set) var answerCardHeight = OverlayLayout.answerCardHeights.lowerBound
    var pendingAnswerStatus: String?
    /// An external action waiting on the answer card for the user's approval.
    var pendingAction: AgentResponse? { pendingExternalAction?.response }
    var resultCanUndo = false
    /// Set while Insert or Undo is writing, so a double click can't paste the same text twice.
    private(set) var isWriting = false
    var overlayErrorSymbol = "exclamationmark"
    var overlayError: String? { didSet { overlayController?.refresh() } }
    /// Buttons after the overlay message, secondary first and primary last; empty for a plain notice.
    private(set) var overlayButtons: [OverlayButton] = []

    /// The floating overlay; set by `AppState.startSystemServices`, so tests run without one.
    @ObservationIgnored var overlayController: FloatingOverlayController?
    @ObservationIgnored var toastHandler: (@MainActor (_ text: String, _ symbol: String) -> Void)?
    @ObservationIgnored var settingsHandler: (@MainActor (SettingsSection) -> Void)?
    /// Opens the permission guide in the main window.
    @ObservationIgnored var permissionGuideHandler: (@MainActor () -> Void)?
    @ObservationIgnored var analyticsHandler: (@MainActor (AnalyticsEvent, Int) -> Void)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let data: LocalData
    @ObservationIgnored private let systemPermissions: SystemPermissionController
    @ObservationIgnored private let audioCapture: any AudioCapturing
    @ObservationIgnored private let realtimeClient: any RealtimeTranscribing
    @ObservationIgnored private let reasoningClient: any Reasoning
    @ObservationIgnored private let textInteraction: any TextWriting
    @ObservationIgnored private let actionExecutor: @MainActor (AgentResponse, SearchEngine) async throws -> Void
    @ObservationIgnored private let soundCues = SoundCues()
    @ObservationIgnored private let signposter = OSSignposter.performance
    /// The workflow whose microphone is starting; nil once it listens or is cancelled.
    @ObservationIgnored private var startingWorkflow: VoiceWorkflowMode?
    @ObservationIgnored private var workflowTask: Task<Void, Never>?
    @ObservationIgnored private var uploadTask: Task<Void, Error>?
    @ObservationIgnored private var chunkContinuation: AsyncStream<Data>.Continuation?
    @ObservationIgnored private var targetSnapshot: TextTargetSnapshot?
    /// A tap starts one capture immediately; the second tap can reuse it for Voice Agent.
    @ObservationIgnored private var fnTapDictation = false
    @ObservationIgnored private var fnTapConfirmed = false
    @ObservationIgnored private var fnTapChunks: AsyncStream<Data>?
    @ObservationIgnored private var finishFnTapWhenReady = false
    /// Recent Voice Agent turns for continuous conversation. Memory only, so quitting clears them.
    @ObservationIgnored private var sessions: [AgentSession] = []
    @ObservationIgnored private var activeAgentSessions: [AgentSession] = []
    @ObservationIgnored private var lastVerifiedWrite: VerifiedWrite?
    @ObservationIgnored private var pendingAnswerTarget: TextTargetSnapshot?
    private var pendingExternalAction: PendingExternalAction?
    @ObservationIgnored private var executingActionHistoryID: UUID?
    @ObservationIgnored private var workflowGeneration = 0
    @ObservationIgnored private var realtimeSessionID = UUID()
    @ObservationIgnored private var recordingLimitTask: Task<Void, Never>?
    @ObservationIgnored private var overlayFeedbackGeneration = 0

    /// Keeps every recording under `QwenReasoningClient.maximumAudioBytes`, so streamed dictation
    /// can still fall back to batch recognition and be retried from History.
    private static let recordingLimit: Duration = .seconds(210)
    private static let recordingLimitWarning: Duration = .seconds(15)
    private static let successDisplayDuration: Duration = .seconds(2)

    init(settings: AppSettings, data: LocalData, dependencies: AppState.Dependencies) {
        self.settings = settings
        self.data = data
        audioCapture = dependencies.audioCapture
        realtimeClient = dependencies.realtimeClient
        reasoningClient = dependencies.reasoningClient
        textInteraction = dependencies.textInteraction
        actionExecutor = dependencies.actionExecutor
        systemPermissions = dependencies.systemPermissions
    }

    func startDictation() {
        beginVoiceWorkflow(mode: .dictation)
    }

    func startFnTapDictation() {
        beginVoiceWorkflow(mode: .dictation, pendingFnTap: true)
    }

    func confirmFnTapDictation() {
        guard fnTapDictation, !fnTapConfirmed else { return }
        fnTapConfirmed = true
        guard targetSnapshot?.hasDictationTarget == true else {
            cancelWorkflow()
            handleWorkflowError(TextInteractionError.noFocusedElement, agent: false)
            return
        }
        if dictationPhase == .listening, let fnTapChunks {
            connectRealtime(streaming: fnTapChunks, generation: workflowGeneration)
            self.fnTapChunks = nil
        }
    }

    /// Switches the still-running capture to Agent without stopping or restarting the microphone.
    @discardableResult
    func promoteFnTapToAgent() -> Bool {
        guard fnTapDictation, dictationIsListening, let snapshot = targetSnapshot else { return false }
        fnTapDictation = false
        fnTapConfirmed = false
        fnTapChunks = nil
        finishFnTapWhenReady = false
        chunkContinuation?.finish()
        chunkContinuation = nil
        if let uploadTask {
            uploadTask.cancel()
            self.uploadTask = nil
            let session = realtimeSessionID
            Task { [realtimeClient] in await realtimeClient.cancel(session: session) }
        }
        let wasStarting = startingWorkflow == .dictation
        if wasStarting {
            startingWorkflow = .agent
            agentPhase = .starting
            dictationPhase = .idle
        }
        prepareWorkflow(mode: .agent, snapshot: snapshot)
        if !wasStarting {
            recordingLimitTask?.cancel()
            agentPhase = .listening
            dictationPhase = .idle
            scheduleRecordingLimit(for: .agent)
        }
        return true
    }

    func toggleDictation() {
        if dictationIsListening { finishDictation() }
        else { startDictation() }
    }

    func cancelDictation() {
        cancelWorkflow()
        playStopCueIfRecording()
        withAnimation(Motion.snappy) { dictationPhase = .idle }
    }

    func finishDictation() {
        guard dictationPhase == .listening else {
            if startingWorkflow == .dictation, fnTapDictation {
                // The engine may already be recording while its start task is waiting to resume.
                if !fnTapConfirmed { confirmFnTapDictation() }
                if dictationIsListening { finishFnTapWhenReady = true }
            } else if startingWorkflow == .dictation {
                cancelDictation()
            }
            return
        }
        if fnTapDictation && !fnTapConfirmed {
            confirmFnTapDictation()
            guard dictationPhase == .listening else { return }
        }
        let recording = stopRecording()
        fnTapDictation = false
        fnTapConfirmed = false
        fnTapChunks = nil
        playSoundCue(.stop)
        let historyID = data.beginHistoryEntry(mode: .dictation, recording: recording, snapshot: targetSnapshot)
        let snapshot = targetSnapshot
        let upload = uploadTask
        let realtimeSession = realtimeSessionID
        targetSnapshot = nil
        let generation = workflowGeneration
        withAnimation(Motion.snappy) { dictationPhase = .processing }
        workflowTask = Task { [weak self] in
            await self?.completeDictation(
                recording, historyID: historyID, snapshot: snapshot,
                upload: upload, realtimeSession: realtimeSession, generation: generation
            )
        }
    }

    func startAgent() {
        if agentIsListening {
            finishAgentListening()
            return
        }
        beginVoiceWorkflow(mode: .agent)
    }

    func finishAgentListening() {
        guard agentPhase == .listening else {
            // Stopped before the microphone opened, so nothing was recorded.
            if startingWorkflow == .agent { dismissAgent() }
            return
        }
        let recording = stopRecording()
        playSoundCue(.stop)
        let historyID = data.beginHistoryEntry(mode: .agent, recording: recording, snapshot: targetSnapshot)
        let snapshot = targetSnapshot
        let context = contextItems
        let conversation = activeAgentSessions
        // Settings can change while the recording is saved; the request uses the ones it started with.
        let key = settings.apiKey
        let requestConfiguration = settings.configuration
        targetSnapshot = nil
        activeAgentSessions = []
        let generation = workflowGeneration
        withAnimation(Motion.snappy) { agentPhase = .transcribing }
        workflowTask = Task { [weak self] in
            await self?.processAgentRecording(
                recording, historyID: historyID, snapshot: snapshot,
                context: context, conversation: conversation,
                apiKey: key, configuration: requestConfiguration, generation: generation
            )
        }
    }

    func dismissAgent() {
        cancelWorkflow()
        playStopCueIfRecording()
        withAnimation(Motion.snappy) { agentPhase = .hidden }
    }

    func cancelActiveVoiceWorkflow() {
        guard dictationPhase.isCancellable || agentPhase.isCancellable || startingWorkflow != nil else { return }
        cancelWorkflow()
        playStopCueIfRecording()
        withAnimation(Motion.snappy) {
            dictationPhase = .idle
            agentPhase = .hidden
        }
    }

    func copyPendingText() {
        guard !pendingCopyText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        hasCopiedPendingText = pasteboard.setString(pendingCopyText, forType: .string)
    }

    var canUndoLastWrite: Bool { lastVerifiedWrite != nil }

    func undoLastWrite() async {
        guard !isWriting, let lastVerifiedWrite else { return }
        isWriting = true
        defer { isWriting = false }
        let generation = workflowGeneration
        do {
            let replacement = try textInteraction.replacementSnapshot(for: lastVerifiedWrite)
            let outcome = try await textInteraction.write(lastVerifiedWrite.target.selectedText, to: replacement)
            guard self.lastVerifiedWrite?.id == lastVerifiedWrite.id else { return }
            self.lastVerifiedWrite = nil
            guard generation == workflowGeneration else { return }
            if dictationPhase == .success { dictationPhase = .idle }
            if agentPhase == .result { agentPhase = .hidden }
            showOverlayFeedback(
                outcome == .verified
                    ? localized("Undone")
                    : localized("Tried to undo. Check the text."),
                symbol: "arrow.uturn.backward"
            )
        } catch {
            if generation == workflowGeneration, self.lastVerifiedWrite?.id == lastVerifiedWrite.id {
                showOverlayFeedback(
                    localized("Can’t undo. The text changed, or this app doesn’t support it."),
                    symbol: "exclamationmark.triangle"
                )
            }
        }
    }

    func dismissAnswer() {
        if let pendingExternalAction { data.updateHistory(pendingExternalAction.historyID, status: .cancelled) }
        clearAnswer()
    }

    private func clearAnswer() {
        pendingAnswerText = ""
        pendingAnswerStatus = nil
        pendingAnswerTarget = nil
        pendingExternalAction = nil
        agentPhase = .hidden
    }

    func copyAnswer() {
        guard !pendingAnswerText.isEmpty else { return }
        pendingCopyText = pendingAnswerText
        copyPendingText()
        pendingAnswerStatus = pendingAction == nil ? localized("Answer copied") : localized("Copied")
    }

    func confirmPendingAction() {
        guard let pendingExternalAction else { return }
        let action = pendingExternalAction.response
        let historyID = pendingExternalAction.historyID
        let session = pendingExternalAction.session
        clearAnswer()
        data.updateHistory(historyID, status: .processing)
        executingActionHistoryID = historyID
        let generation = workflowGeneration
        let engine = settings.searchEngine
        agentCommand = action.intent ?? action.action.title
        withAnimation(Motion.panel) { agentPhase = .processing }
        // Stored as the workflow so the pill's cancel button stops a running shortcut.
        workflowTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.actionExecutor(action, engine)
                guard generation == self.workflowGeneration else { return }
                self.data.updateHistory(historyID, status: .completed)
                self.analyticsHandler?(.voiceAgent, 0)
                if let session { self.sessions = AgentSession.appending(session, to: self.sessions) }
                self.executingActionHistoryID = nil
                await self.showAgentResult(generation: generation)
            } catch {
                // A cancel bumps the generation first, so only real failures get past this guard.
                guard generation == self.workflowGeneration else { return }
                self.executingActionHistoryID = nil
                self.finishFailedWorkflow(error, historyID: historyID, agent: true, generation: generation)
            }
        }
    }

    func insertAnswer() async {
        guard !isWriting, let snapshot = pendingAnswerTarget, !pendingAnswerText.isEmpty else { return }
        isWriting = true
        defer { isWriting = false }
        let answer = pendingAnswerText
        let generation = workflowGeneration
        do {
            let outcome = try await textInteraction.write(answer, to: snapshot)
            guard generation == workflowGeneration, pendingAnswerText == answer else { return }
            lastVerifiedWrite = outcome == .verified ? VerifiedWrite(target: snapshot, text: answer) : nil
            dismissAnswer()
            showOverlayFeedback(localized("Inserted"), symbol: "checkmark")
        } catch {
            if generation == workflowGeneration, pendingAnswerText == answer {
                pendingAnswerStatus = localized("The text field changed. Copy the answer instead.")
            }
        }
    }

    func dismissCopyFallback() {
        let wasDictation = dictationPhase == .copyReady
        let wasAgent = agentPhase == .copyReady
        cancelWorkflow()
        if wasDictation { dictationPhase = .idle }
        if wasAgent { agentPhase = .hidden }
    }

    func retryDictation(_ id: UUID) async {
        guard let index = data.historyEntries.firstIndex(where: { $0.id == id }),
              data.historyEntries[index].canRetryTranscription else { return }
        let entry = data.historyEntries[index]
        guard !settings.apiKey.isEmpty else {
            showToast(QwenError.missingConfiguration.localizedDescription, symbol: "key.fill")
            return
        }
        data.historyEntries[index].status = .processing
        data.historyEntries[index].errorMessage = nil
        do {
            let wav = try await data.audio(for: entry)
            let result = try await reasoningClient.transcribeAudio(
                apiKey: settings.apiKey,
                configuration: settings.configuration,
                wav: wav,
                recognitionLanguage: settings.recognitionLanguage,
                numberFormat: settings.dictationNumberFormat,
                cleanup: settings.dictationCleanup,
                // A retry lands in History, not in an app, so there is no tone to match.
                targetApp: nil,
                memoryPrompt: renderMemoryPrompt(.transcription)
            )
            let cleaned = try SpeechDisfluencyCleaner.dictation(result, mode: settings.dictationCleanup)
            data.updateHistory(id, input: cleaned, output: cleaned, status: .completed)
            showToast(localized("Transcribed again"), symbol: "checkmark")
        } catch {
            data.updateHistory(id, status: .failed, errorMessage: localizedError(error))
        }
    }

    private enum VoiceWorkflowMode: Sendable { case dictation, agent }

    private func beginVoiceWorkflow(mode: VoiceWorkflowMode, pendingFnTap: Bool = false) {
        cancelWorkflow()
        dictationPhase = .idle
        agentPhase = .hidden
        // Shortcuts usually fire from another app, so explain on the overlay and open the fix.
        guard systemPermissions.microphoneStatus == .authorized else {
            showOverlayFeedback(localized("Allow microphone access first"), symbol: "mic.slash", duration: .seconds(4))
            showPermissionGuide()
            return
        }
        guard !settings.apiKey.isEmpty else {
            let message = QwenError.missingConfiguration.localizedDescription
            showOverlayFeedback(message, symbol: "key.fill", duration: .seconds(4))
            showSettings(section: .qwen)
            showToast(message, symbol: "key.fill")
            return
        }
        // A hard block: the microphone must not even turn on in a password field or manager.
        // `captureTarget` still checks the focused element for a secure text field.
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        guard !TextInteraction.isSensitiveWithoutAccessibility(bundleID: frontmostBundleID) else {
            handleWorkflowError(TextInteractionError.sensitiveTarget, agent: mode == .agent)
            return
        }
        overlayController?.resetAnchor()
        fnTapDictation = pendingFnTap
        fnTapConfirmed = false
        let generation = workflowGeneration
        let pillInterval = signposter.beginInterval("Fn to Pill", id: signposter.makeSignpostID())
        // Buffer realtime audio while the connection is established after the microphone opens.
        let chunks: AsyncStream<Data>?
        let onChunk: @Sendable (Data) -> Void
        if mode == .dictation && settings.configuration.realtimeURL != nil {
            let (stream, continuation) = AsyncStream<Data>.makeStream()
            chunks = stream
            chunkContinuation = continuation
            onChunk = { continuation.yield($0) }
        } else {
            chunks = nil
            onChunk = { _ in }
        }
        fnTapChunks = pendingFnTap ? chunks : nil
        var engineStart: Task<Void, Error>?
        do {
            let snapshot = try signposter.withIntervalSignpost("captureTarget") {
                try textInteraction.captureTarget(
                    requiringWindow: mode == .dictation && !pendingFnTap,
                    includingCaretFrame: settings.overlayPlacement == .caret,
                    onSafeTarget: {
                        // The secure-field and target checks have passed. Start the engine on its
                        // queue while Accessibility reads the remaining target details.
                        startingWorkflow = mode
                        engineStart = startAudioCapture(for: mode, onChunk: onChunk)
                        // The pill can appear before optional Accessibility reads finish.
                        if mode == .agent { agentPhase = .starting }
                        else { dictationPhase = .starting }
                    }
                )
            }
            guard !snapshot.isSensitive else { throw TextInteractionError.sensitiveTarget }
            overlayController?.anchor(to: snapshot)
            prepareWorkflow(mode: mode, snapshot: snapshot)
        } catch {
            signposter.endInterval("Fn to Pill", pillInterval)
            handleWorkflowError(error, agent: mode == .agent)
            return
        }
        guard let engineStart else {
            signposter.endInterval("Fn to Pill", pillInterval)
            handleWorkflowError(AudioCaptureError.microphoneUnavailable, agent: mode == .agent)
            return
        }
        Task { [weak self] in
            let started = await engineStart.result
            // Whatever bumped the generation also cancelled the capture, which stopped this engine.
            guard let self else { return }
            guard generation == self.workflowGeneration else {
                self.signposter.endInterval("Fn to Pill", pillInterval)
                return
            }
            let activeMode = self.startingWorkflow ?? mode
            self.startingWorkflow = nil
            do {
                try started.get()
            } catch {
                self.signposter.endInterval("Fn to Pill", pillInterval)
                self.handleWorkflowError(error, agent: activeMode == .agent)
                return
            }
            self.signposter.endInterval("Fn to Pill", pillInterval)
            let finishAfterStart = activeMode == .dictation && self.finishFnTapWhenReady
            self.finishFnTapWhenReady = false
            self.startListening(
                mode: activeMode, chunks: chunks, generation: generation,
                playStartCue: !finishAfterStart
            )
            if finishAfterStart { self.finishDictation() }
        }
    }

    private func prepareWorkflow(mode: VoiceWorkflowMode, snapshot: TextTargetSnapshot) {
        targetSnapshot = snapshot
        liveTranscript = ""
        inputLevel = 0
        pendingCopyText = ""
        activeAgentSessions = []
        guard mode == .agent else { return }
        let conversation = settings.continuousConversation
            ? AgentSession.conversation(in: sessions, app: snapshot.bundleID)
            : []
        activeAgentSessions = conversation
        contextItems = ContextCollector.collect(
            snapshot: snapshot,
            selectedTextAllowed: settings.selectedTextAllowed,
            currentAppAllowed: settings.currentAppAllowed,
            windowTitleAllowed: settings.windowTitleAllowed,
            clipboardAllowed: settings.clipboardAllowed,
            browserPage: settings.browserPageAllowed ? textInteraction.browserPageAddress(in: snapshot) : nil,
            screenText: settings.screenTextAllowed ? textInteraction.visibleText(in: snapshot) : "",
            sessions: conversation,
            domains: settings.selectedDomains,
            memory: data.memoryEntities
        )
        // After a deletion the last write is kept only for undo; there is nothing left to revise.
        if let lastVerifiedWrite, lastVerifiedWrite.isRecent, !lastVerifiedWrite.text.isEmpty,
           let expected = lastVerifiedWrite.expectedValue,
           snapshot.valueBefore == expected,
           textInteraction.currentValue(of: lastVerifiedWrite.target) == expected {
            contextItems.append(ContextCollector.previousOutputItem(lastVerifiedWrite.text))
        }
        agentCommand = localized("Listening…")
    }

    /// Changes the pill to listening only once the engine runs.
    private func startListening(
        mode: VoiceWorkflowMode, chunks: AsyncStream<Data>?, generation: Int,
        playStartCue: Bool = true
    ) {
        if mode == .agent {
            agentPhase = .listening
        } else {
            withAnimation(Motion.spring) { dictationPhase = .listening }
        }
        if mode == .dictation, let chunks, (!fnTapDictation || fnTapConfirmed) {
            connectRealtime(streaming: chunks, generation: generation)
            fnTapChunks = nil
        }
        if playStartCue {
            playSoundCue(.start)
            scheduleRecordingLimit(for: mode)
        }
    }

    /// Chunks recorded before the connection is ready wait in the stream.
    private func connectRealtime(streaming chunks: AsyncStream<Data>, generation: Int) {
        let shouldAutoStop = settings.autoStop
        let selectedRecognitionLanguage = settings.recognitionLanguage
        let selectedNumberFormat = settings.dictationNumberFormat
        let selectedCleanup = settings.dictationCleanup
        let targetApp = toneTargetApp(for: targetSnapshot)
        let memoryPrompt = renderMemoryPrompt(.transcription)
        let realtimeSession = UUID()
        realtimeSessionID = realtimeSession
        let connectInterval = signposter.beginInterval("realtime connect", id: signposter.makeSignpostID())
        uploadTask = Task { [weak self, realtimeClient, apiKey = settings.apiKey, configuration = settings.configuration, selectedRecognitionLanguage, selectedNumberFormat, selectedCleanup, targetApp, memoryPrompt] in
            try await realtimeClient.connect(
                session: realtimeSession,
                apiKey: apiKey,
                configuration: configuration,
                autoStop: shouldAutoStop,
                onSpeechStopped: {
                    Task { @MainActor in
                        guard let self, self.workflowGeneration == generation, self.dictationIsListening else { return }
                        self.finishDictation()
                    }
                },
                onDelta: { transcript in
                    Task { @MainActor in
                        guard let self, self.workflowGeneration == generation, self.dictationIsListening else { return }
                        self.liveTranscript = transcript
                    }
                },
                recognitionLanguage: selectedRecognitionLanguage,
                numberFormat: selectedNumberFormat,
                cleanup: selectedCleanup,
                targetApp: targetApp,
                memoryPrompt: memoryPrompt
            )
            self?.signposter.endInterval("realtime connect", connectInterval)
            for await chunk in chunks { try await realtimeClient.append(chunk, session: realtimeSession) }
        }
    }

    /// Warns shortly before the recording cap, then finishes the recording as if the user had stopped it.
    private func scheduleRecordingLimit(for mode: VoiceWorkflowMode) {
        let generation = workflowGeneration
        let warning = Self.recordingLimitWarning
        recordingLimitTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.recordingLimit - warning)
                if let self, self.workflowGeneration == generation {
                    let seconds = warning.components.seconds
                    self.showOverlayFeedback(
                        localized("Recording stops in \(seconds) seconds"),
                        symbol: "timer"
                    )
                }
                try await Task.sleep(for: warning)
            } catch {
                return
            }
            guard let self, self.workflowGeneration == generation else { return }
            self.finishListening(for: mode)
        }
    }

    private func finishListening(for mode: VoiceWorkflowMode) {
        if mode == .agent { finishAgentListening() } else { finishDictation() }
    }

    /// Errors stay silent; the overlay already reports them.
    private func playSoundCue(_ cue: SoundCues.Cue) {
        guard settings.soundCuesEnabled else { return }
        soundCues.play(cue)
    }

    /// For cancel paths: `cancelWorkflow` leaves the phases alone, so they still show whether a recording just ended.
    private func playStopCueIfRecording() {
        if isRecording { playSoundCue(.stop) }
    }

    private func stopRecording() -> AudioCapture.Recording {
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
        let recording = audioCapture.stop()
        inputLevel = 0
        chunkContinuation?.finish()
        chunkContinuation = nil
        return recording
    }

    /// Queues the engine start off the main thread at once; the returned task finishes once it runs.
    private func startAudioCapture(
        for mode: VoiceWorkflowMode, onChunk: @escaping @Sendable (Data) -> Void
    ) -> Task<Void, Error> {
        let generation = workflowGeneration
        return audioCapture.start(
            onLevel: { [weak self] level in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.inputLevel = AudioLevel.smoothed(previous: self.inputLevel, next: level)
                }
            },
            onChunk: onChunk,
            onInterruption: { [weak self] in
                // Keep what was heard so far, as if the user had stopped the recording.
                Task { @MainActor [weak self] in
                    guard let self, self.workflowGeneration == generation,
                          self.dictationIsListening || self.agentIsListening else { return }
                    self.finishListening(for: self.agentIsListening ? .agent : mode)
                    self.showOverlayFeedback(
                        localized("Audio device changed. Recording stopped."),
                        symbol: "mic.slash"
                    )
                }
            }
        )
    }

    private func completeDictation(
        _ recording: AudioCapture.Recording, historyID: UUID?,
        snapshot: TextTargetSnapshot?, upload: Task<Void, Error>?,
        realtimeSession: UUID, generation: Int
    ) async {
        await persistHistoryAudio(recording, historyID: historyID)
        do {
            let transcript = try await transcribe(
                recording, upload: upload, realtimeSession: realtimeSession,
                targetApp: toneTargetApp(for: snapshot), generation: generation
            )
            try Task.checkCancellation()
            guard generation == workflowGeneration else { throw CancellationError() }
            guard !transcript.isEmpty else { throw QwenError.invalidResponse }
            guard let snapshot else { throw TextInteractionError.targetChanged }
            let raw = DictationTextJoiner.join(transcript, to: snapshot)
            data.updateHistory(historyID, input: transcript, output: raw)
            do {
                let outcome = try await textInteraction.write(raw, to: snapshot)
                data.updateHistory(historyID, status: .completed)
                try Task.checkCancellation()
                guard generation == workflowGeneration else { throw CancellationError() }
                let verifiedWrite = outcome == .verified ? VerifiedWrite(target: snapshot, text: raw) : nil
                lastVerifiedWrite = verifiedWrite
                if let verifiedWrite {
                    observeCorrection(writtenText: raw, snapshot: snapshot, writeID: verifiedWrite.id)
                }
            } catch is TextInteractionError {
                // A write can still fail after a cancel; the copy fallback must not replace the user's
                // clipboard or cover a newer recording.
                try Task.checkCancellation()
                guard generation == workflowGeneration else { throw CancellationError() }
                data.updateHistory(historyID, status: .completed)
                presentCopyFallback(raw, agent: false)
                analyticsHandler?(.voiceInput, raw.count)
                await realtimeClient.cancel(session: realtimeSession)
                return
            }
            withAnimation(Motion.spring) { dictationPhase = .success }
            analyticsHandler?(.voiceInput, raw.count)
            try? await Task.sleep(for: Self.successDisplayDuration)
            if generation == workflowGeneration, dictationPhase == .success {
                withAnimation(Motion.snappy) { dictationPhase = .idle }
            }
        } catch is CancellationError {
            data.updateHistory(historyID, status: .cancelled)
            if generation == workflowGeneration, dictationPhase == .processing { dictationPhase = .idle }
        } catch {
            finishFailedWorkflow(error, historyID: historyID, agent: false, generation: generation)
        }
        await realtimeClient.cancel(session: realtimeSession)
    }

    private func processAgentRecording(
        _ recording: AudioCapture.Recording, historyID: UUID?,
        snapshot: TextTargetSnapshot?, context: [ContextItem],
        conversation: [AgentSession], apiKey: String,
        configuration: QwenConfiguration, generation: Int
    ) async {
        await persistHistoryAudio(recording, historyID: historyID)
        do {
            try Task.checkCancellation()
            guard generation == workflowGeneration else { throw CancellationError() }
            guard recording.hasSpeech else { throw QwenError.noSpeech }
            let memoryPrompt = context
                .filter { $0.kind == .memory || $0.kind == .domain }
                .map(\.value)
                .joined(separator: "\n")
            let response = try await reasoningClient.respondToAudio(
                apiKey: apiKey,
                configuration: configuration,
                wav: recording.wav,
                context: context,
                sessions: context.contains(where: { $0.kind == .session }) ? conversation : [],
                textField: snapshot?.agentTextField ?? .absent,
                matchAppTone: settings.matchAppTone,
                memoryPrompt: memoryPrompt
            )
            try Task.checkCancellation()
            guard generation == workflowGeneration else { throw CancellationError() }
            guard let transcript = response.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !transcript.isEmpty else { throw QwenError.invalidResponse }
            let command = SpeechDisfluencyCleaner.clean(transcript, mode: .light)
            guard let snapshot else { throw TextInteractionError.targetChanged }
            // An empty result is not worth keeping; the Session still records the deletion.
            if response.deletesPrevious, let historyID { data.deleteHistoryEntry(historyID) }
            data.updateHistory(historyID, input: command)
            agentCommand = response.intent ?? response.action.title
            withAnimation(Motion.panel) { agentPhase = .processing }
            await executeAgent(
                response, snapshot: snapshot, context: context,
                command: command, historyID: historyID, generation: generation
            )
        } catch is CancellationError {
            data.updateHistory(historyID, status: .cancelled)
            if generation == workflowGeneration, agentPhase == .transcribing || agentPhase == .processing {
                agentPhase = .hidden
            }
        } catch {
            finishFailedWorkflow(error, historyID: historyID, agent: true, generation: generation)
        }
    }

    /// `upload` is nil when dictation skipped realtime, so the recording goes straight to batch recognition.
    private func transcribe(
        _ recording: AudioCapture.Recording, upload: Task<Void, Error>?,
        realtimeSession: UUID, targetApp: String?, generation: Int
    ) async throws -> String {
        guard recording.hasSpeech else {
            throw QwenError.noSpeech
        }
        if let upload {
            do {
                try await upload.value
                try Task.checkCancellation()
                guard generation == workflowGeneration else { throw CancellationError() }
                // The final text of a longer recording takes longer to arrive.
                let result = try await realtimeClient.commit(
                    session: realtimeSession,
                    timeout: .seconds(15 + recording.duration / 4)
                )
                return try SpeechDisfluencyCleaner.dictation(result, mode: settings.dictationCleanup)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                guard generation == workflowGeneration else { throw CancellationError() }
                // Batch recognition only helps with transport problems; configuration errors would fail twice.
                guard QwenError.allowsBatchFallback(after: error) else { throw error }
                Log.qwen.notice("Realtime failed with \(Log.describe(error), privacy: .public); falling back to batch")
                await realtimeClient.cancel(session: realtimeSession)
            }
        }
        let result = try await reasoningClient.transcribeAudio(
            apiKey: settings.apiKey,
            configuration: settings.configuration,
            wav: recording.wav,
            recognitionLanguage: settings.recognitionLanguage,
            numberFormat: settings.dictationNumberFormat,
            cleanup: settings.dictationCleanup,
            targetApp: targetApp,
            memoryPrompt: renderMemoryPrompt(.transcription)
        )
        return try SpeechDisfluencyCleaner.dictation(result, mode: settings.dictationCleanup)
    }

    /// The app dictation asks the model to match in tone. Nil keeps the tone rule out of the prompt:
    /// the setting is off, cleanup is verbatim, or the target is sensitive.
    private func toneTargetApp(for snapshot: TextTargetSnapshot?) -> String? {
        guard settings.matchAppTone, settings.dictationCleanup == .light, let snapshot, !snapshot.isSensitive else { return nil }
        return snapshot.promptAppName
    }

    /// Saved memory and domain presets for dictation.
    private func renderMemoryPrompt(_ purpose: MemoryPrompt.Purpose) -> String {
        MemoryPrompt.render(
            entities: data.memoryEntities,
            domains: settings.selectedDomains,
            purpose: purpose
        )
    }

    private func executeAgent(
        _ response: AgentResponse, snapshot: TextTargetSnapshot,
        context: [ContextItem], command: String, historyID: UUID?, generation: Int
    ) async {
        do {
            try Task.checkCancellation()
            guard generation == workflowGeneration else { throw CancellationError() }
            let output: String
            var needsCopyFallback = false
            var actionToConfirm: AgentResponse?
            if response.action == .writeText {
                // Generated text is final prose, not a speech trace; cleaning it could alter names or code.
                guard let text = response.output, !text.isEmpty || response.deletesPrevious else {
                    throw QwenError.invalidResponse
                }
                if settings.automaticAgentWriteBack, !AgentActionExecutor.replacesClippedText(response, context: context) {
                    do {
                        let writeTarget: TextTargetSnapshot
                        if response.target == .previous {
                            guard context.contains(where: { $0.kind == .previousOutput }),
                                  let lastVerifiedWrite else { throw TextInteractionError.targetChanged }
                            writeTarget = try textInteraction.replacementSnapshot(for: lastVerifiedWrite)
                        } else {
                            writeTarget = snapshot
                        }
                        let outcome = try await textInteraction.write(text, to: writeTarget)
                        try Task.checkCancellation()
                        guard generation == workflowGeneration else { throw CancellationError() }
                        lastVerifiedWrite = outcome == .verified ? VerifiedWrite(target: writeTarget, text: text) : nil
                        resultCanUndo = outcome == .verified
                    } catch let error as TextInteractionError {
                        // A deletion has no text to copy instead.
                        guard !text.isEmpty else { throw error }
                        needsCopyFallback = true
                    }
                } else {
                    guard !text.isEmpty else { throw AgentActionError.deleteNeedsInsert }
                    needsCopyFallback = true
                }
                output = text
            } else if response.action == .answer {
                guard let text = response.output, !text.isEmpty else { throw QwenError.invalidResponse }
                output = text
            } else if AgentActionExecutor.needsConfirmation(response, context: context) {
                // Checked now so the card never offers an action that cannot run.
                try AgentActionExecutor.validate(response, engine: settings.searchEngine)
                actionToConfirm = response
                output = response.url ?? response.query ?? response.shortcutName ?? ""
            } else {
                resultCanUndo = false
                try await actionExecutor(response, settings.searchEngine)
                output = response.url ?? response.query ?? response.shortcutName ?? ""
            }
            try Task.checkCancellation()
            guard generation == workflowGeneration else { throw CancellationError() }
            let session: AgentSession? = settings.continuousConversation
                ? AgentSession(
                    app: snapshot.bundleID,
                    contextSummary: QwenReasoningClient.sessionContextSummary(context: context, response: response),
                    userCommand: command,
                    response: output,
                    expiresAt: .now.addingTimeInterval(AgentSession.ttl)
                ) : nil
            data.updateHistory(
                historyID, input: command, output: output,
                status: actionToConfirm == nil ? .completed : .awaitingConfirmation
            )
            if actionToConfirm == nil {
                analyticsHandler?(.voiceAgent, response.action == .writeText || response.action == .answer ? output.count : 0)
            }
            if actionToConfirm == nil, let session { sessions = AgentSession.appending(session, to: sessions) }
            if needsCopyFallback {
                presentCopyFallback(output, agent: true, copyImmediately: settings.automaticAgentWriteBack)
                return
            }
            if response.action == .answer || actionToConfirm != nil {
                pendingAnswerText = output
                answerCardHeight = OverlayLayout.answerCardHeight(for: output)
                pendingAnswerTarget = snapshot
                pendingExternalAction = actionToConfirm.map {
                    PendingExternalAction(response: $0, historyID: historyID, session: session)
                }
                withAnimation(Motion.panel) { agentPhase = .answerReady }
                return
            }
            await showAgentResult(generation: generation)
        } catch is CancellationError {
            data.updateHistory(historyID, status: .cancelled)
            if generation == workflowGeneration { agentPhase = .hidden }
        } catch {
            finishFailedWorkflow(error, historyID: historyID, agent: true, generation: generation)
        }
    }

    private func showAgentResult(generation: Int) async {
        withAnimation(Motion.panel) { agentPhase = .result }
        try? await Task.sleep(for: Self.successDisplayDuration)
        if generation == workflowGeneration, agentPhase == .result {
            withAnimation(Motion.snappy) { agentPhase = .hidden }
        }
    }

    /// A workflow superseded by a cancel or a new recording is recorded as cancelled, not failed.
    private func finishFailedWorkflow(_ error: Error, historyID: UUID?, agent: Bool, generation: Int) {
        guard generation == workflowGeneration else {
            data.updateHistory(historyID, status: .cancelled)
            return
        }
        data.updateHistory(historyID, status: .failed, errorMessage: localizedError(error))
        handleWorkflowError(error, agent: agent)
    }

    private func persistHistoryAudio(_ recording: AudioCapture.Recording, historyID: UUID?) async {
        let saved = await data.persistHistoryAudio(recording, historyID: historyID)
        // The user is usually in another app, where only the overlay is visible.
        if !saved {
            showOverlayFeedback(
                localized("Couldn’t save this to History. Transcription will continue."),
                symbol: "exclamationmark.triangle"
            )
        }
    }

    private func cancelWorkflow() {
        workflowGeneration += 1
        if let pendingExternalAction { data.updateHistory(pendingExternalAction.historyID, status: .cancelled) }
        data.updateHistory(executingActionHistoryID, status: .cancelled)
        executingActionHistoryID = nil
        startingWorkflow = nil
        fnTapDictation = false
        fnTapConfirmed = false
        fnTapChunks = nil
        finishFnTapWhenReady = false
        workflowTask?.cancel()
        workflowTask = nil
        uploadTask?.cancel()
        uploadTask = nil
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
        chunkContinuation?.finish()
        chunkContinuation = nil
        audioCapture.cancel()
        inputLevel = 0
        // Scoped to the old session, so it cannot close a session started after this call.
        let realtimeSession = realtimeSessionID
        Task { [realtimeClient] in await realtimeClient.cancel(session: realtimeSession) }
        targetSnapshot = nil
        activeAgentSessions = []
        pendingCopyText = ""
        pendingAnswerText = ""
        pendingAnswerStatus = nil
        pendingAnswerTarget = nil
        pendingExternalAction = nil
        resultCanUndo = false
        overlayButtons = []
        overlayError = nil
    }

    private func presentCopyFallback(_ text: String, agent: Bool, copyImmediately: Bool = true) {
        pendingCopyText = text
        if copyImmediately { copyPendingText() }
        withAnimation(Motion.panel) {
            if agent { agentPhase = .copyReady }
            else { dictationPhase = .copyReady }
        }
    }

    private func handleWorkflowError(_ error: Error, agent: Bool) {
        // Logged before the phase resets; `idle` or `hidden` means the pill never showed.
        let stage = agent ? "agent \(agentPhase)" : "dictation \(dictationPhase)"
        let level: OSLogType = (error as? QwenError) == .noSpeech ? .info : .error
        Log.workflow.log(level: level, "Workflow failed in \(stage, privacy: .public): \(Log.describe(error), privacy: .public)")
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
        startingWorkflow = nil
        fnTapDictation = false
        fnTapConfirmed = false
        fnTapChunks = nil
        finishFnTapWhenReady = false
        audioCapture.cancel()
        inputLevel = 0
        chunkContinuation?.finish()
        chunkContinuation = nil
        uploadTask?.cancel()
        if agent { agentPhase = .hidden } else { dictationPhase = .idle }
        targetSnapshot = nil
        let message = localizedError(error)
        let symbol = (error as? QwenError)?.symbol ?? "exclamationmark"
        if (error as? QwenError) == .noSpeech {
            showOverlayFeedback(message, symbol: symbol)
            return
        }
        // The overlay is the only surface visible from other apps; the toast only helps inside SayKuku.
        showOverlayFeedback(message, symbol: symbol, duration: .seconds(4))
        if Self.needsSettings(error) {
            showSettings(section: .qwen)
            // The overlay already says what went wrong; the toast explains why Settings opened.
            showToast(localized("Opened Settings › Qwen Connection"), symbol: "gearshape")
        } else if NSApplication.shared.isActive {
            showToast(message, symbol: "exclamationmark.triangle.fill")
        }
    }

    private static func needsSettings(_ error: Error) -> Bool {
        guard let qwenError = error as? QwenError else { return false }
        switch qwenError {
        case .missingConfiguration, .invalidEndpoint: return true
        // 400 also covers content inspection and bad audio, which Settings cannot fix.
        case .server(let status, _): return [401, 403].contains(status)
        default: return false
        }
    }

    private func showOverlayFeedback(
        _ message: String, symbol: String, duration: Duration = .seconds(2.4), buttons: [OverlayButton] = []
    ) {
        overlayFeedbackGeneration += 1
        let generation = overlayFeedbackGeneration
        overlayErrorSymbol = symbol
        overlayButtons = buttons
        overlayError = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, self.overlayFeedbackGeneration == generation else { return }
            self.overlayButtons = []
            withAnimation(Motion.snappy) { self.overlayError = nil }
        }
    }

    /// Runs an overlay button, then closes the message unless the button showed another one.
    func pressOverlayButton(at index: Int) {
        guard overlayButtons.indices.contains(index) else { return }
        let action = overlayButtons[index].action
        let generation = overlayFeedbackGeneration
        overlayButtons = []
        action()
        guard generation == overlayFeedbackGeneration else { return }
        withAnimation(Motion.snappy) { overlayError = nil }
    }

    /// Counts a correction the user just made and, until it has been asked about twice, offers to
    /// remember it on the overlay, where the user can see it from any app.
    func noteCorrection(_ change: CorrectionCandidate, app: String, windowTitle: String) {
        // The message would cover a recording that started since the write; the suggestion waits in Memory.
        let isBusy = dictationPhase != .idle || agentPhase != .hidden || startingWorkflow != nil
        guard let record = data.recordCorrection(change, app: app, windowTitle: windowTitle, canPrompt: !isBusy) else {
            return
        }
        showOverlayFeedback(
            localized("Remember “\(record.raw)” as “\(record.corrected)”?"),
            symbol: "brain",
            duration: .seconds(8),
            buttons: [
                OverlayButton(title: localized("Not Now")),
                OverlayButton(title: localized("Remember")) { [weak self] in
                    self?.data.acceptCorrection(record.id)
                    self?.showOverlayFeedback(localized("Remembered"), symbol: "checkmark")
                }
            ]
        )
    }

    private func observeCorrection(writtenText: String, snapshot: TextTargetSnapshot, writeID: UUID) {
        guard settings.learnFromCorrections, let before = snapshot.valueBefore, let range = snapshot.selectedRange else { return }
        let source = before as NSString
        guard range.location >= 0, range.length >= 0, NSMaxRange(NSRange(location: range.location, length: range.length)) <= source.length else { return }
        let expected = source.replacingCharacters(in: NSRange(location: range.location, length: range.length), with: writtenText)
        let writtenRange = range.location..<(range.location + (writtenText as NSString).length)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.settings.learnFromCorrections, self.lastVerifiedWrite?.id == writeID,
                  let actual = self.textInteraction.currentValue(of: snapshot),
                  let change = CorrectionExtractor.extract(expected: expected, actual: actual, writtenRange: writtenRange) else { return }
            self.noteCorrection(change, app: snapshot.appName, windowTitle: snapshot.windowTitle)
        }
    }

    private func showToast(_ text: String, symbol: String) {
        toastHandler?(text, symbol)
    }

    private func showSettings(section: SettingsSection) {
        settingsHandler?(section)
    }

    private func showPermissionGuide() {
        permissionGuideHandler?()
    }
}
