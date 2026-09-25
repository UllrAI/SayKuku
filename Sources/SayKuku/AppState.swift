import AppKit
import AVFoundation
import Observation
import os
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
@Observable
final class AppState {
    enum Destination: String, CaseIterable, Identifiable {
        case home = "Home", history = "History", knowledge = "Knowledge"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .home: "house"
            case .history: "clock.arrow.circlepath"
            case .knowledge: "books.vertical"
            }
        }
        var title: String {
            switch self {
            case .home: localized("Home")
            case .history: localized("History")
            case .knowledge: localized("Memory")
            }
        }
    }

    enum DictationPhase: Equatable {
        case idle, listening, processing, success, copyReady

        /// Recording or waiting on the model. Finished states close on their own or from their card.
        var isCancellable: Bool { self == .listening || self == .processing }
    }

    enum AgentPhase: Equatable {
        case hidden, listening, transcribing, processing, result, copyReady, answerReady

        /// Recording or waiting on the model. Finished states close on their own or from their card.
        var isCancellable: Bool { self == .listening || self == .transcribing || self == .processing }
    }
    enum ConnectionState: Equatable {
        case idle, testing, failed(String)
        /// `realtimeMilliseconds` is nil when realtime was skipped for lack of a workspace ID.
        case connected(realtimeMilliseconds: Int?, chatMilliseconds: Int)
    }

    enum ShortcutStatus: Equatable {
        case starting, ready, accessibilityRequired
        /// Enabled shortcuts that could not be registered, usually because another app owns them.
        case hotKeyConflict([GlobalShortcutAction])
        var symbol: String {
            switch self {
            case .starting: "clock"
            case .ready: "checkmark.circle"
            case .accessibilityRequired, .hotKeyConflict: "exclamationmark.triangle"
            }
        }
        @MainActor func title(_ appState: AppState) -> String {
            let shortcutsOff = GlobalShortcutAction.allCases.allSatisfy { appState.settings.globalShortcut(for: $0) == nil }
            switch self {
            case .starting:
                return localized("Starting shortcuts…")
            case .ready:
                return shortcutsOff
                    ? localized("Fn ready · Global shortcuts off")
                    : localized("Fn and global shortcuts ready")
            case .accessibilityRequired:
                return shortcutsOff
                    ? localized("Fn needs Accessibility · Global shortcuts off")
                    : localized("Global shortcuts ready · Fn needs Accessibility")
            case .hotKeyConflict(let actions):
                guard actions.count == 1, let action = actions.first else {
                    return localized("Both global shortcuts are already in use by other apps. Record new ones.")
                }
                let keys = appState.settings.globalShortcut(for: action)?.displayString ?? ""
                return localized("\(keys) for \(action.title) is already in use by another app. Record a new one.")
            }
        }
    }

    var destination: Destination = .home
    var settingsSection: SettingsSection = .general
    var dictationPhase: DictationPhase = .idle { didSet { overlayController?.refresh() } }
    var agentPhase: AgentPhase = .hidden { didSet { overlayController?.refresh() } }
    /// True while the microphone is capturing for either workflow.
    var isRecording: Bool { dictationPhase == .listening || agentPhase == .listening }
    /// Also true while the microphone is still starting. The pill waits for it, but a release,
    /// second press or Esc in that window must stop the start instead of going unheard.
    var dictationIsListening: Bool { dictationPhase == .listening || startingWorkflow == .dictation }
    var agentIsListening: Bool { agentPhase == .listening || startingWorkflow == .agent }
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
    /// A link or shortcut the answer card asks about first, because the model chose it while reading untrusted context.
    var pendingAction: AgentResponse?
    var resultCanUndo = false
    /// Set while Insert or Undo is writing, so a double click can't paste the same text twice.
    private(set) var isWriting = false
    var overlayErrorSymbol = "exclamationmark"
    var overlayError: String? { didSet { overlayController?.refresh() } }
    /// Buttons after the overlay message, secondary first and primary last; empty for a plain notice.
    private(set) var overlayButtons: [OverlayButton] = []
    var toast: ToastMessage?
    var shortcutStatus: ShortcutStatus = .starting
    var presentedSheet: AppSheet? {
        // Covers every close path (buttons, Esc, dismiss()) without relying on sheet onDismiss.
        didSet { if presentedSheet == nil, oldValue != nil { presentNextSetupStep() } }
    }
    /// Where the sheet on screen sits in the first-run flow; nil outside that flow.
    private(set) var setupProgress: SetupProgress?
    var launchAtLogin = false
    var connectionState: ConnectionState = .idle
    let settings: AppSettings
    let data: LocalData
    let systemPermissions: SystemPermissionController
    let microphoneTest = MicrophoneTestController()

    @ObservationIgnored private let audioCapture: any AudioCapturing
    @ObservationIgnored private let realtimeClient: any RealtimeTranscribing
    @ObservationIgnored private let reasoningClient: any Reasoning
    @ObservationIgnored private let textInteraction: any TextWriting
    @ObservationIgnored private let soundCues = SoundCues()
    @ObservationIgnored private let signposter = OSSignposter.performance
    /// The workflow whose microphone is starting; nil once it listens or is cancelled.
    @ObservationIgnored private var startingWorkflow: VoiceWorkflowMode?
    @ObservationIgnored private var shortcutController: ShortcutController?
    @ObservationIgnored private var overlayController: FloatingOverlayController?
    @ObservationIgnored private var workflowTask: Task<Void, Never>?
    @ObservationIgnored private var uploadTask: Task<Void, Error>?
    @ObservationIgnored private var chunkContinuation: AsyncStream<Data>.Continuation?
    @ObservationIgnored private var targetSnapshot: TextTargetSnapshot?
    /// Recent Voice Agent turns for continuous conversation. Memory only, so quitting clears them.
    @ObservationIgnored private var sessions: [AgentSession] = []
    @ObservationIgnored private var activeAgentSessions: [AgentSession] = []
    @ObservationIgnored private var lastVerifiedWrite: VerifiedWrite?
    @ObservationIgnored private var pendingAnswerTarget: TextTargetSnapshot?
    @ObservationIgnored private var workflowGeneration = 0
    @ObservationIgnored private var realtimeSessionID = UUID()
    @ObservationIgnored private var recordingLimitTask: Task<Void, Never>?
    @ObservationIgnored private var overlayFeedbackGeneration = 0
    @ObservationIgnored private var mainWindowOpener: OpenWindowAction?
    @ObservationIgnored private var settingsOpener: OpenSettingsAction?
    /// Sparkle's controller; nil in dev builds, which never update themselves.
    @ObservationIgnored private(set) var updater: SPUStandardUpdaterController?
    @ObservationIgnored private var didEvaluateStartupPermissions = false
    @ObservationIgnored private var pendingSetupSteps: [AppSheet] = []

    static let mainWindowID = "main"
    /// Keeps every recording under `QwenReasoningClient.maximumAudioBytes`, so streamed dictation
    /// can still fall back to batch recognition and be retried from History.
    private static let recordingLimit: Duration = .seconds(210)
    private static let recordingLimitWarning: Duration = .seconds(15)
    private static let successDisplayDuration: Duration = .seconds(2)

    /// The microphone, Qwen, focused-app and permission services the voice workflows drive; tests pass fakes.
    struct Dependencies {
        var audioCapture: any AudioCapturing
        var realtimeClient: any RealtimeTranscribing
        var reasoningClient: any Reasoning
        var textInteraction: any TextWriting
        var systemPermissions: SystemPermissionController

        /// New instances on every call, so no two states share an engine or a socket.
        @MainActor static var live: Dependencies {
            Dependencies(
                audioCapture: AudioCapture(),
                realtimeClient: QwenRealtimeClient(),
                reasoningClient: QwenReasoningClient(),
                textInteraction: TextInteraction(),
                systemPermissions: SystemPermissionController()
            )
        }
    }

    init(
        defaults: UserDefaults = .standard,
        store: LocalStore = LocalStore(),
        keychain: KeychainStore = KeychainStore(),
        persistenceDelay: Duration = .milliseconds(500),
        dependencies: Dependencies = .live
    ) {
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        self.settings = settings
        data = LocalData(store: store, settings: settings, persistenceDelay: persistenceDelay)
        audioCapture = dependencies.audioCapture
        realtimeClient = dependencies.realtimeClient
        reasoningClient = dependencies.reasoningClient
        textInteraction = dependencies.textInteraction
        systemPermissions = dependencies.systemPermissions
        launchAtLogin = SMAppService.mainApp.status == .enabled
        systemPermissions.accessibilityChangeHandler = { [weak self] in self?.refreshSystemPermissions() }
        settings.qwenConnectionChangeHandler = { [weak self] in self?.invalidateConnectionTest() }
        settings.historyRetentionChangeHandler = { [weak self] in self?.data.cleanExpiredHistory() }
        data.toastHandler = { [weak self] text, symbol in self?.showToast(text, symbol: symbol) }
        settings.globalShortcutChangeHandler = { [weak self] in self?.shortcutController?.reloadHotKeys() }
    }

    func startDictation() {
        beginVoiceWorkflow(mode: .dictation)
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
            // Stopped before the microphone opened, so nothing was recorded.
            if startingWorkflow == .dictation { cancelDictation() }
            return
        }
        let recording = stopRecording()
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
        pendingAnswerText = ""
        pendingAnswerStatus = nil
        pendingAnswerTarget = nil
        pendingAction = nil
        agentPhase = .hidden
    }

    func copyAnswer() {
        guard !pendingAnswerText.isEmpty else { return }
        pendingCopyText = pendingAnswerText
        copyPendingText()
        pendingAnswerStatus = pendingAction == nil ? localized("Answer copied") : localized("Copied")
    }

    func confirmPendingAction() {
        guard let action = pendingAction else { return }
        dismissAnswer()
        let generation = workflowGeneration
        let engine = settings.searchEngine
        agentCommand = action.intent ?? action.action.title
        withAnimation(Motion.panel) { agentPhase = .processing }
        // Stored as the workflow so the pill's cancel button stops a running shortcut.
        workflowTask = Task { [weak self] in
            do {
                try await AgentActionExecutor.execute(action, engine: engine)
                guard let self, generation == self.workflowGeneration else { return }
                await self.showAgentResult(generation: generation)
            } catch {
                // A cancel bumps the generation first, so only real failures get past this guard.
                guard let self, generation == self.workflowGeneration else { return }
                self.handleWorkflowError(error, agent: true)
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

    func startSystemServices() {
        guard shortcutController == nil else { return }
        overlayController = FloatingOverlayController(appState: self)
        let controller = ShortcutController(appState: self)
        shortcutController = controller
        controller.start()
        Task { await data.loadStoredData() }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.presentStartupExperienceIfNeeded()
        }
    }

    func analyzeKnowledge(_ source: String) async throws -> KnowledgeAnalysis {
        let redacted = KnowledgePipeline.redactingPII(in: source)
        var entities: [ProposedEntity] = []
        for chunk in KnowledgePipeline.chunks(redacted.text) {
            entities += try await reasoningClient.extractKnowledge(apiKey: settings.apiKey, configuration: settings.configuration, text: chunk)
        }
        return KnowledgePipeline.analyze(proposals: entities, existing: data.knowledgeEntities, ignored: redacted.ignored)
    }

    /// Commits pending edits, then tests the saved credentials.
    func testQwenConnection(_ draft: QwenCredentialsDraft) async {
        guard connectionState != .testing, commitQwenCredentials(draft), !settings.apiKey.isEmpty else { return }
        await runConnectionTest()
    }

    /// Saves whatever changed in the typed credentials. A Keychain failure shows in the connection status.
    @discardableResult
    func commitQwenCredentials(_ draft: QwenCredentialsDraft) -> Bool {
        let workspaceID = draft.workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if workspaceID != settings.qwenWorkspaceID { settings.qwenWorkspaceID = workspaceID }
        let key = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key != settings.apiKey else { return true }
        do {
            try settings.saveAPIKey(key)
            return true
        } catch {
            connectionState = .failed(localizedError(error))
            return false
        }
    }

    private func runConnectionTest() async {
        let key = settings.apiKey
        let tested = settings.configuration
        connectionState = .testing
        // A client of its own, so testing never tears down a dictation in progress.
        let testClient = QwenRealtimeClient()
        let realtimeSession = UUID()
        do {
            // Without a workspace ID there is no realtime endpoint to test; dictation uses batch recognition.
            var realtimeMilliseconds: Int?
            if tested.realtimeURL != nil {
                let started = ContinuousClock.now
                try await testClient.connect(
                    session: realtimeSession,
                    apiKey: key,
                    configuration: tested,
                    autoStop: false,
                    onSpeechStopped: {},
                    onDelta: { _ in }
                )
                realtimeMilliseconds = Int(started.duration(to: .now) / Duration.milliseconds(1))
                await testClient.cancel(session: realtimeSession)
            }
            let chatLatency = try await reasoningClient.testConnection(apiKey: key, configuration: tested)
            finishConnectionTest(
                .connected(
                    realtimeMilliseconds: realtimeMilliseconds,
                    chatMilliseconds: Int(chatLatency / Duration.milliseconds(1))
                ),
                apiKey: key, configuration: tested
            )
        } catch {
            await testClient.cancel(session: realtimeSession)
            finishConnectionTest(.failed(localizedError(error)), apiKey: key, configuration: tested)
        }
    }

    /// Keeps a running test locked, but marks any finished result as outdated.
    private func invalidateConnectionTest() {
        if connectionState != .testing { connectionState = .idle }
    }

    /// Drops the result when the key or connection settings changed mid-test.
    private func finishConnectionTest(_ result: ConnectionState, apiKey key: String, configuration tested: QwenConfiguration) {
        connectionState = settings.apiKey == key && settings.configuration == tested ? result : .idle
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
                knowledgePrompt: renderKnowledgePrompt(.transcription)
            )
            let cleaned = try SpeechDisfluencyCleaner.dictation(result, mode: settings.dictationCleanup)
            data.updateHistory(id, input: cleaned, output: cleaned, status: .completed)
            showToast(localized("Transcribed again"), symbol: "checkmark")
        } catch {
            data.updateHistory(id, status: .failed, errorMessage: localizedError(error))
        }
    }

    func copyHistoryOutput(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast(localized("Copied"), symbol: "doc.on.doc")
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func presentPermissionGuideIfNeeded() {
        systemPermissions.refresh()
        guard !didEvaluateStartupPermissions else { return }
        didEvaluateStartupPermissions = true
        if !systemPermissions.allRequiredPermissionsGranted { presentedSheet = .permissions }
    }
    func showDomainOnboarding() { presentedSheet = .onboarding }
    func completeDomainOnboarding(domains: Set<DomainPreset>) {
        if !settings.didCompleteOnboarding { pendingSetupSteps = [.permissions, .qwenSetup] }
        settings.selectedDomains = domains
        settings.didCompleteOnboarding = true
        presentedSheet = nil
    }

    /// Walks the remaining first-run steps after a sheet closes.
    private func presentNextSetupStep() {
        guard !pendingSetupSteps.isEmpty else {
            setupProgress = nil
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, self.presentedSheet == nil else { return }
            while !self.pendingSetupSteps.isEmpty {
                let step = self.pendingSetupSteps.removeFirst()
                if self.isSetupStepNeeded(step) {
                    let number = (self.setupProgress?.step ?? 0) + 1
                    // Steps already done elsewhere (say, a permission granted meanwhile) drop out of the count.
                    let remaining = self.pendingSetupSteps.filter { self.isSetupStepNeeded($0) }.count
                    self.setupProgress = SetupProgress(step: number, total: number + remaining)
                    self.presentedSheet = step
                    return
                }
            }
            self.setupProgress = nil
        }
    }

    /// Primary button of a setup sheet: Continue mid-flow, Done on the last step or outside the flow.
    var setupContinueTitle: String {
        setupProgress?.isLastStep == false ? localized("Continue") : localized("Done")
    }

    /// Secondary button of a setup sheet that leaves the step unfinished.
    var setupSkipTitle: String {
        setupProgress == nil ? localized("Not Now") : localized("Skip")
    }

    private func isSetupStepNeeded(_ step: AppSheet) -> Bool {
        switch step {
        case .onboarding:
            return false
        case .permissions:
            systemPermissions.refresh()
            return !systemPermissions.allRequiredPermissionsGranted
        case .qwenSetup:
            return settings.apiKey.isEmpty
        }
    }

    func showPermissionGuide() { systemPermissions.refresh(); presentedSheet = .permissions }
    func dismissPermissionGuide() { microphoneTest.stop(); presentedSheet = nil }
    func refreshSystemPermissions() {
        let wasGranted = systemPermissions.accessibilityStatus.isAuthorized
        systemPermissions.refresh()
        if systemPermissions.accessibilityStatus.isAuthorized, !wasGranted || shortcutStatus == .accessibilityRequired {
            shortcutController?.refreshAccessibilityPermission()
        }
    }
    @discardableResult func requestPermission(_ kind: SystemPermissionKind) async -> Bool {
        let granted = await systemPermissions.request(kind); refreshSystemPermissions(); return granted
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            showToast(
                localized("Couldn’t update Login Items. Check System Settings › General › Login Items."),
                symbol: "exclamationmark.triangle.fill"
            )
        }
    }
    func setGlobalShortcutsPaused(_ paused: Bool) { shortcutController?.setHotKeysPaused(paused) }
    func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    /// Opens a new instance, then quits this one, so a new `appLanguage` takes effect.
    func relaunch() {
        // Release the global shortcuts first: the new instance registers them before this one quits.
        setGlobalShortcutsPaused(true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { @Sendable _, error in
            Task { @MainActor in
                guard let error else {
                    NSApplication.shared.terminate(nil)
                    return
                }
                self.setGlobalShortcutsPaused(false)
                Log.workflow.error("Relaunch failed: \(Log.describe(error), privacy: .public)")
                self.showToast(
                    localized("Couldn’t reopen SayKuku. Quit and open it again."),
                    symbol: "exclamationmark.triangle.fill"
                )
            }
        }
    }
    func showToast(_ text: String, symbol: String) {
        let message = ToastMessage(text: text, symbol: symbol)
        withAnimation(Motion.snappy) { toast = message }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard self?.toast?.id == message.id else { return }
            withAnimation(Motion.snappy) { self?.toast = nil }
        }
    }

    func registerMainWindowOpener(_ openWindow: OpenWindowAction) {
        mainWindowOpener = openWindow
    }

    /// Brings the main window forward even when it was closed or the Dock icon is hidden.
    func showMainWindow(destination: Destination? = nil) {
        if let destination { self.destination = destination }
        NSApplication.shared.setActivationPolicy(.regular)
        mainWindowOpener?.callAsFunction(id: Self.mainWindowID)
        NSApplication.shared.activate()
    }

    func registerSettingsOpener(_ openSettings: OpenSettingsAction) {
        settingsOpener = openSettings
    }

    func registerUpdater(_ updater: SPUStandardUpdaterController) {
        self.updater = updater
    }

    /// Opens the Settings window on its own; a hidden Dock icon stays hidden.
    func showSettings(section: SettingsSection? = nil) {
        if let section { settingsSection = section }
        NSApplication.shared.activate()
        settingsOpener?.callAsFunction()
    }

    private enum VoiceWorkflowMode: Sendable { case dictation, agent }

    private func beginVoiceWorkflow(mode: VoiceWorkflowMode) {
        cancelWorkflow()
        dictationPhase = .idle
        agentPhase = .hidden
        // Shortcuts usually fire from another app, so explain on the overlay and open the fix.
        guard systemPermissions.microphoneStatus == .authorized else {
            showOverlayFeedback(localized("Allow microphone access first"), symbol: "mic.slash", duration: .seconds(4))
            showPermissionGuide()
            showMainWindow()
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
        let generation = workflowGeneration
        let pillInterval = signposter.beginInterval("Fn to Pill", id: signposter.makeSignpostID())
        // Realtime needs a workspace ID; without one the full recording goes to batch recognition.
        let chunks: AsyncStream<Data>?
        let onChunk: @Sendable (Data) -> Void
        if mode == .dictation && settings.configuration.realtimeURL != nil {
            // Holds the audio until the Realtime connection is ready to take it.
            let (stream, continuation) = AsyncStream<Data>.makeStream()
            chunks = stream
            chunkContinuation = continuation
            onChunk = { continuation.yield($0) }
        } else {
            chunks = nil
            onChunk = { _ in }
        }
        // The engine starts on its own queue while this thread reads the target app.
        let engineStart = startAudioCapture(for: mode, onChunk: onChunk)
        startingWorkflow = mode
        do {
            let snapshot = try signposter.withIntervalSignpost("captureTarget") {
                try textInteraction.captureTarget(
                    requiringWindow: mode == .dictation, includingCaretFrame: settings.overlayPlacement == .caret
                )
            }
            overlayController?.anchor(to: snapshot)
            guard !snapshot.isSensitive else { throw TextInteractionError.sensitiveTarget }
            prepareWorkflow(mode: mode, snapshot: snapshot)
        } catch {
            startingWorkflow = nil
            // `AudioCapture.cancel` runs after the pending start, so this also stops that engine.
            handleWorkflowError(error, agent: mode == .agent)
            return
        }
        Task { [weak self] in
            let started = await engineStart.result
            // Whatever bumped the generation also cancelled the capture, which stopped this engine.
            guard let self, generation == self.workflowGeneration else { return }
            self.startingWorkflow = nil
            do {
                try started.get()
            } catch {
                self.handleWorkflowError(error, agent: mode == .agent)
                return
            }
            self.signposter.endInterval("Fn to Pill", pillInterval)
            self.startListening(mode: mode, chunks: chunks, generation: generation)
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
            session: conversation.last,
            domains: settings.selectedDomains,
            knowledge: data.knowledgeEntities
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

    /// Shows the pill only once the target is read and the engine runs, so it still means the microphone is open.
    private func startListening(mode: VoiceWorkflowMode, chunks: AsyncStream<Data>?, generation: Int) {
        if mode == .agent {
            agentPhase = .listening
        } else {
            withAnimation(Motion.spring) { dictationPhase = .listening }
        }
        if let chunks { connectRealtime(streaming: chunks, generation: generation) }
        playSoundCue(.start)
        scheduleRecordingLimit(for: mode)
    }

    /// Chunks recorded before the connection is ready wait in the stream.
    private func connectRealtime(streaming chunks: AsyncStream<Data>, generation: Int) {
        let shouldAutoStop = settings.autoStop
        let selectedRecognitionLanguage = settings.recognitionLanguage
        let selectedNumberFormat = settings.dictationNumberFormat
        let selectedCleanup = settings.dictationCleanup
        let targetApp = toneTargetApp(for: targetSnapshot)
        let knowledgePrompt = renderKnowledgePrompt(.transcription)
        let realtimeSession = UUID()
        realtimeSessionID = realtimeSession
        let connectInterval = signposter.beginInterval("realtime connect", id: signposter.makeSignpostID())
        uploadTask = Task { [weak self, realtimeClient, apiKey = settings.apiKey, configuration = settings.configuration, selectedRecognitionLanguage, selectedNumberFormat, selectedCleanup, targetApp, knowledgePrompt] in
            try await realtimeClient.connect(
                session: realtimeSession,
                apiKey: apiKey,
                configuration: configuration,
                autoStop: shouldAutoStop,
                onSpeechStopped: {
                    Task { @MainActor in
                        guard self?.workflowGeneration == generation else { return }
                        self?.finishDictation()
                    }
                },
                onDelta: { transcript in
                    Task { @MainActor in
                        guard self?.workflowGeneration == generation else { return }
                        self?.liveTranscript = transcript
                    }
                },
                recognitionLanguage: selectedRecognitionLanguage,
                numberFormat: selectedNumberFormat,
                cleanup: selectedCleanup,
                targetApp: targetApp,
                knowledgePrompt: knowledgePrompt
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
                    self.inputLevel = (self.inputLevel * 0.55) + (level * 0.45)
                }
            },
            onChunk: onChunk,
            onInterruption: { [weak self] in
                // Keep what was heard so far, as if the user had stopped the recording.
                Task { @MainActor [weak self] in
                    guard let self, self.workflowGeneration == generation,
                          self.dictationIsListening || self.agentIsListening else { return }
                    self.finishListening(for: mode)
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
                await realtimeClient.cancel(session: realtimeSession)
                return
            }
            withAnimation(Motion.spring) { dictationPhase = .success }
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
            let knowledgePrompt = renderKnowledgePrompt(
                .agent,
                includesKnowledge: context.contains { $0.kind == .knowledge },
                includesDomains: context.contains { $0.kind == .domain }
            )
            let response = try await reasoningClient.respondToAudio(
                apiKey: apiKey,
                configuration: configuration,
                wav: recording.wav,
                context: context,
                sessions: context.contains(where: { $0.kind == .session }) ? conversation : [],
                textField: snapshot?.agentTextField ?? .absent,
                matchAppTone: settings.matchAppTone,
                knowledgePrompt: knowledgePrompt
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
            knowledgePrompt: renderKnowledgePrompt(.transcription)
        )
        return try SpeechDisfluencyCleaner.dictation(result, mode: settings.dictationCleanup)
    }

    /// The app dictation asks the model to match in tone. Nil keeps the tone rule out of the prompt:
    /// the setting is off, cleanup is verbatim, or the target is sensitive.
    private func toneTargetApp(for snapshot: TextTargetSnapshot?) -> String? {
        guard settings.matchAppTone, settings.dictationCleanup == .light, let snapshot, !snapshot.isSensitive else { return nil }
        return snapshot.promptAppName
    }

    /// Saved knowledge and domain presets for a prompt; the Agent leaves out whichever the user removed from its context.
    private func renderKnowledgePrompt(
        _ purpose: KnowledgePrompt.Purpose, includesKnowledge: Bool = true, includesDomains: Bool = true
    ) -> String {
        KnowledgePrompt.render(
            entities: includesKnowledge ? data.knowledgeEntities : [],
            domains: includesDomains ? settings.selectedDomains : [],
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
                        data.updateHistory(historyID, input: command, output: text, status: .completed)
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
                try await AgentActionExecutor.execute(response, engine: settings.searchEngine)
                output = response.url ?? response.query ?? response.shortcutName ?? ""
            }
            data.updateHistory(historyID, input: command, output: output, status: .completed)
            if settings.continuousConversation {
                sessions = AgentSession.appending(AgentSession(
                    app: snapshot.bundleID,
                    contextSummary: QwenReasoningClient.sessionContextSummary(context: context, response: response),
                    userCommand: command,
                    response: output,
                    expiresAt: .now.addingTimeInterval(AgentSession.ttl)
                ), to: sessions)
            }
            // A write or action can finish after the user dismissed this workflow or started a new one.
            guard generation == workflowGeneration else { return }
            if needsCopyFallback {
                presentCopyFallback(output, agent: true, copyImmediately: settings.automaticAgentWriteBack)
                return
            }
            if response.action == .answer || actionToConfirm != nil {
                pendingAnswerText = output
                answerCardHeight = OverlayLayout.answerCardHeight(for: output)
                pendingAnswerTarget = snapshot
                pendingAction = actionToConfirm
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
        startingWorkflow = nil
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
        pendingAction = nil
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
            duration: .seconds(6),
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

    /// Errors that adopt `LocalizedError` describe themselves; system errors such as `URLError`
    /// don't, so they get a plain message rather than Foundation's, which follows the system language.
    func localizedError(_ error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription { return description }
        if error is URLError { return localized("Couldn’t connect. Check your network and try again.") }
        return localized("Something went wrong. Try again.")
    }

    private func presentStartupExperienceIfNeeded() {
        if settings.didCompleteOnboarding {
            presentPermissionGuideIfNeeded()
        } else {
            let laterSteps = [AppSheet.permissions, .qwenSetup].filter { isSetupStepNeeded($0) }
            setupProgress = SetupProgress(step: 1, total: 1 + laterSteps.count)
            presentedSheet = .onboarding
        }
    }
}

struct SetupProgress: Equatable {
    let step: Int
    let total: Int

    var isLastStep: Bool { step >= total }

    var title: String {
        localized("Step \(step) of \(total)")
    }
}

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let symbol: String
}
