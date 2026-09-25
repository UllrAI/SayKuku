import AppKit
import AVFoundation
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppState {
    enum Destination: String, CaseIterable, Identifiable {
        case home = "Home", history = "History", knowledge = "Knowledge", memory = "Memory"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .home: "house"
            case .history: "clock.arrow.circlepath"
            case .knowledge: "books.vertical"
            case .memory: "sparkles.rectangle.stack"
            }
        }
        @MainActor func title(_ appState: AppState) -> String {
            switch self {
            case .home: appState.text("首页", "Home")
            case .history: appState.text("历史", "History")
            case .knowledge: appState.text("知识", "Knowledge")
            case .memory: appState.text("记忆", "Memory")
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
            let shortcutsOff = GlobalShortcutAction.allCases.allSatisfy { appState.globalShortcut(for: $0) == nil }
            switch self {
            case .starting:
                return appState.text("正在启动快捷键…", "Starting shortcuts…")
            case .ready:
                return shortcutsOff
                    ? appState.text("Fn 已就绪 · 全局快捷键已关闭", "Fn ready · Global shortcuts off")
                    : appState.text("Fn 与全局快捷键已就绪", "Fn and global shortcuts ready")
            case .accessibilityRequired:
                return shortcutsOff
                    ? appState.text("Fn 需要辅助功能权限 · 全局快捷键已关闭", "Fn needs Accessibility · Global shortcuts off")
                    : appState.text("全局快捷键可用 · Fn 需要辅助功能权限", "Global shortcuts ready · Fn needs Accessibility")
            case .hotKeyConflict(let actions):
                guard actions.count == 1, let action = actions.first else {
                    return appState.text(
                        "两个全局快捷键都已被其他 App 占用，请重新设置",
                        "Both global shortcuts are already in use by other apps. Record new ones."
                    )
                }
                let keys = appState.globalShortcut(for: action)?.displayString ?? ""
                return appState.text(
                    "\(keys)（\(action.title(appState))）已被其他 App 占用，请重新设置",
                    "\(keys) for \(action.title(appState)) is already in use by another app. Record a new one."
                )
            }
        }
    }

    var destination: Destination = .home
    var settingsSection: SettingsSection = .general
    var appLanguage: AppLanguage = .system { didSet { defaults.set(appLanguage.rawValue, forKey: Keys.language) } }
    var dictationPhase: DictationPhase = .idle { didSet { overlayController?.refresh() } }
    var agentPhase: AgentPhase = .hidden { didSet { overlayController?.refresh() } }
    /// True while the microphone is capturing for either workflow.
    var isRecording: Bool { dictationPhase == .listening || agentPhase == .listening }
    var inputMode: InputMode = .hold { didSet { defaults.set(inputMode.rawValue, forKey: Keys.inputMode) } }
    var autoStop = false { didSet { defaults.set(autoStop, forKey: Keys.autoStop) } }
    var recognitionLanguage: RecognitionLanguage = .automatic {
        didSet { defaults.set(recognitionLanguage.rawValue, forKey: Keys.recognitionLanguage) }
    }
    var dictationNumberFormat: DictationNumberFormat = .preferDigits {
        didSet { defaults.set(dictationNumberFormat.rawValue, forKey: Keys.dictationNumberFormat) }
    }
    var dictationCleanup: DictationCleanup = .light {
        didSet { defaults.set(dictationCleanup.rawValue, forKey: Keys.dictationCleanup) }
    }
    var selectedDomains: Set<DomainPreset> = [] {
        didSet { defaults.set(selectedDomains.map(\.rawValue).sorted(), forKey: Keys.selectedDomains) }
    }
    var didCompleteOnboarding = false {
        didSet { defaults.set(didCompleteOnboarding, forKey: Keys.didCompleteOnboarding) }
    }
    var continuousConversation = true { didSet { defaults.set(continuousConversation, forKey: Keys.continuousConversation) } }
    var automaticAgentWriteBack = true {
        didSet { defaults.set(automaticAgentWriteBack, forKey: Keys.automaticAgentWriteBack) }
    }
    /// Nil until the user picks an engine, so the default keeps following the region.
    private var storedSearchEngine: SearchEngine? = nil {
        didSet { defaults.set(storedSearchEngine?.rawValue, forKey: Keys.searchEngine) }
    }
    var searchEngine: SearchEngine {
        get { storedSearchEngine ?? SearchEngine.defaultEngine(for: qwenRegion) }
        set { storedSearchEngine = newValue }
    }
    var learnFromCorrections = true { didSet { defaults.set(learnFromCorrections, forKey: Keys.learnCorrections) } }
    var soundCuesEnabled = true { didSet { defaults.set(soundCuesEnabled, forKey: Keys.soundCues) } }
    var selectedTextAllowed = true { didSet { defaults.set(selectedTextAllowed, forKey: Keys.selectedText) } }
    var currentAppAllowed = true { didSet { defaults.set(currentAppAllowed, forKey: Keys.currentApp) } }
    var windowTitleAllowed = true { didSet { defaults.set(windowTitleAllowed, forKey: Keys.windowTitle) } }
    var clipboardAllowed = false { didSet { defaults.set(clipboardAllowed, forKey: Keys.clipboard) } }
    var browserPageAllowed = false { didSet { defaults.set(browserPageAllowed, forKey: Keys.browserPage) } }
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
    var toast: ToastMessage?
    var historyEntries: [HistoryEntry] = [] { didSet { schedulePersistence() } }
    var knowledgeEntities: [KnowledgeEntity] = [] { didSet { schedulePersistence() } }
    var corrections: [CorrectionRecord] = [] { didSet { schedulePersistence() } }
    var sessions: [AgentSession] = [] { didSet { schedulePersistence() } }
    var historyRetention: HistoryRetention = .days30 {
        didSet { defaults.set(historyRetention.rawValue, forKey: Keys.historyRetention); cleanExpiredHistory() }
    }
    var storeVoiceAudio = true { didSet { defaults.set(storeVoiceAudio, forKey: Keys.storeVoiceAudio) } }
    private(set) var localDataIssue: LocalStore.DataIssue?
    private(set) var legacyDataURL: URL?
    var shortcutStatus: ShortcutStatus = .starting
    var presentedSheet: AppSheet? {
        // Covers every close path (buttons, Esc, dismiss()) without relying on sheet onDismiss.
        didSet { if presentedSheet == nil, oldValue != nil { presentNextSetupStep() } }
    }
    /// Where the sheet on screen sits in the first-run flow; nil outside that flow.
    private(set) var setupProgress: SetupProgress?
    private(set) var showInMenuBar = true { didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) } }
    var hideDockIconAfterMainWindowCloses = false {
        didSet {
            defaults.set(hideDockIconAfterMainWindowCloses, forKey: Keys.hideDockIconAfterMainWindowCloses)
            if hideDockIconAfterMainWindowCloses { showInMenuBar = true }
        }
    }
    var launchAtLogin = false
    var qwenRegion: QwenRegion = .beijing {
        didSet { defaults.set(qwenRegion.rawValue, forKey: Keys.qwenRegion); invalidateConnectionTest() }
    }
    var qwenWorkspaceID = "" {
        didSet { defaults.set(qwenWorkspaceID, forKey: Keys.qwenWorkspace); invalidateConnectionTest() }
    }
    var realtimeModel = QwenModelCatalog.defaultRealtimeModel {
        didSet { defaults.set(realtimeModel, forKey: Keys.realtimeModel); invalidateConnectionTest() }
    }
    var reasoningModel = QwenModelCatalog.defaultReasoningModel {
        didSet { defaults.set(reasoningModel, forKey: Keys.reasoningModel); invalidateConnectionTest() }
    }
    /// The saved key; edits stay in a view draft until `commitQwenCredentials` runs.
    private(set) var apiKey = ""
    var connectionState: ConnectionState = .idle
    let systemPermissions = SystemPermissionController()
    let microphoneTest = MicrophoneTestController()
    // nil means the shortcut is turned off; Fn gestures keep working either way.
    var voiceInputShortcut: GlobalShortcut? = .defaultVoiceInput {
        didSet { saveGlobalShortcut(voiceInputShortcut, forKey: Keys.voiceInputShortcut) }
    }
    var voiceAgentShortcut: GlobalShortcut? = .defaultVoiceAgent {
        didSet { saveGlobalShortcut(voiceAgentShortcut, forKey: Keys.voiceAgentShortcut) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let audioCapture = AudioCapture()
    @ObservationIgnored private let realtimeClient = QwenRealtimeClient()
    @ObservationIgnored private let reasoningClient = QwenReasoningClient()
    @ObservationIgnored private let textInteraction = TextInteraction()
    @ObservationIgnored private let soundCues = SoundCues()
    @ObservationIgnored private var shortcutController: ShortcutController?
    @ObservationIgnored private var overlayController: FloatingOverlayController?
    @ObservationIgnored private var workflowTask: Task<Void, Never>?
    @ObservationIgnored private var uploadTask: Task<Void, Error>?
    @ObservationIgnored private var chunkContinuation: AsyncStream<Data>.Continuation?
    @ObservationIgnored private var targetSnapshot: TextTargetSnapshot?
    @ObservationIgnored private var activeAgentSessions: [AgentSession] = []
    @ObservationIgnored private var lastVerifiedWrite: VerifiedWrite?
    @ObservationIgnored private var pendingAnswerTarget: TextTargetSnapshot?
    @ObservationIgnored private var workflowGeneration = 0
    @ObservationIgnored private var realtimeSessionID = UUID()
    @ObservationIgnored private var recordingLimitTask: Task<Void, Never>?
    @ObservationIgnored private var overlayFeedbackGeneration = 0
    @ObservationIgnored private var mainWindowOpener: OpenWindowAction?
    @ObservationIgnored private var settingsOpener: OpenSettingsAction?
    @ObservationIgnored private var didEvaluateStartupPermissions = false
    @ObservationIgnored private var pendingSetupSteps: [AppSheet] = []
    @ObservationIgnored private var didStartLoading = false
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var persistenceGeneration = 0
    @ObservationIgnored private let persistenceDelay: Duration
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?

    static let mainWindowID = "main"
    /// Keeps every recording under `QwenReasoningClient.maximumAudioBytes`, so streamed dictation
    /// can still fall back to batch recognition and be retried from History.
    private static let recordingLimit: Duration = .seconds(210)
    private static let recordingLimitWarning: Duration = .seconds(15)
    private static let successDisplayDuration: Duration = .seconds(2)

    init(
        defaults: UserDefaults = .standard,
        store: LocalStore = LocalStore(),
        keychain: KeychainStore = KeychainStore(),
        persistenceDelay: Duration = .milliseconds(500)
    ) {
        self.defaults = defaults
        self.store = store
        self.keychain = keychain
        self.persistenceDelay = persistenceDelay
        loadSettings()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        apiKey = (try? keychain.string(for: Keys.apiKey)) ?? ""
        systemPermissions.accessibilityChangeHandler = { [weak self] in self?.refreshSystemPermissions() }
    }

    var usesChineseUI: Bool {
        switch appLanguage {
        case .chinese: true
        case .english: false
        case .system: Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        }
    }

    var configuration: QwenConfiguration {
        QwenConfiguration(region: qwenRegion, workspaceID: qwenWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines), realtimeModel: realtimeModel, reasoningModel: reasoningModel)
    }

    func text(_ chinese: String, _ english: String) -> String { usesChineseUI ? chinese : english }
    var voiceInputTitle: String { text("语音输入", "Voice Input") }
    var voiceAgentTitle: String { text("语音 Agent", "Voice Agent") }

    func setShowInMenuBar(_ isVisible: Bool) {
        guard isVisible || !hideDockIconAfterMainWindowCloses else { return }
        showInMenuBar = isVisible
    }

    func startDictation() {
        beginVoiceWorkflow(mode: .dictation)
    }

    func toggleDictation() {
        if dictationPhase == .listening { finishDictation() }
        else { startDictation() }
    }

    func cancelDictation() {
        cancelWorkflow()
        playStopCueIfRecording()
        withAnimation(Motion.snappy) { dictationPhase = .idle }
    }

    func finishDictation() {
        guard dictationPhase == .listening else { return }
        let recording = stopRecording()
        playSoundCue(.stop)
        let historyID = beginHistoryEntry(mode: .dictation, recording: recording)
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
        if agentPhase == .listening {
            finishAgentListening()
            return
        }
        beginVoiceWorkflow(mode: .agent)
    }

    func finishAgentListening() {
        guard agentPhase == .listening else { return }
        let recording = stopRecording()
        playSoundCue(.stop)
        let historyID = beginHistoryEntry(mode: .agent, recording: recording)
        let snapshot = targetSnapshot
        let context = contextItems
        let conversation = activeAgentSessions
        // Settings can change while the recording is saved; the request uses the ones it started with.
        let key = apiKey
        let requestConfiguration = configuration
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
        guard dictationPhase.isCancellable || agentPhase.isCancellable else { return }
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
                    ? text("已撤销", "Undone")
                    : text("已尝试撤销，请核对", "Tried to undo. Check the text."),
                symbol: "arrow.uturn.backward"
            )
        } catch {
            if generation == workflowGeneration, self.lastVerifiedWrite?.id == lastVerifiedWrite.id {
                showOverlayFeedback(
                    text("无法撤销，文字已被改动，或这个 App 不支持撤销", "Can’t undo. The text changed, or this app doesn’t support it."),
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
        pendingAnswerStatus = pendingAction == nil ? text("已复制回答", "Answer copied") : text("已复制", "Copied")
    }

    func confirmPendingAction() {
        guard let action = pendingAction else { return }
        dismissAnswer()
        let generation = workflowGeneration
        let engine = searchEngine
        agentCommand = action.intent ?? action.action.title(isChineseUI: usesChineseUI)
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
            showOverlayFeedback(text("已输入", "Inserted"), symbol: "checkmark")
        } catch {
            if generation == workflowGeneration, pendingAnswerText == answer {
                pendingAnswerStatus = text("输入位置变了，请复制回答后手动粘贴", "The text field changed. Copy the answer instead.")
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
        Task { await loadStoredData() }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.presentStartupExperienceIfNeeded()
        }
    }

    func analyzeKnowledge(_ source: String) async throws -> KnowledgeAnalysis {
        let redacted = KnowledgePipeline.redactingPII(in: source)
        var entities: [ProposedEntity] = []
        for chunk in KnowledgePipeline.chunks(redacted.text) {
            entities += try await reasoningClient.extractKnowledge(apiKey: apiKey, configuration: configuration, text: chunk)
        }
        return KnowledgePipeline.analyze(proposals: entities, existing: knowledgeEntities, ignored: redacted.ignored)
    }

    func commitKnowledge(_ analysis: KnowledgeAnalysis, selectedIDs: Set<UUID>) {
        knowledgeEntities = KnowledgePipeline.commit(analysis: analysis, selectedIDs: selectedIDs, existing: knowledgeEntities)
    }

    /// Returns why the item couldn't be saved, or `nil` once it's added.
    func addKnowledge(name: String, type: EntityType, detail: String? = nil, aliases: [String] = []) -> KnowledgeSaveError? {
        if let error = insertKnowledge(KnowledgeEntity(name: name, detail: detail ?? "", type: type, aliases: aliases)) {
            return error
        }
        showToast(text("已加入知识", "Added to Knowledge"), symbol: "checkmark.circle.fill")
        return nil
    }

    /// Adds the item without a toast; returns why it couldn't be added.
    private func insertKnowledge(_ candidate: KnowledgeEntity) -> KnowledgeSaveError? {
        if let error = validateKnowledge(candidate) { return error }
        knowledgeEntities.insert(candidate, at: 0)
        return nil
    }

    /// Returns why the edit couldn't be saved, or `nil` once it's applied.
    func updateKnowledge(
        id: UUID,
        name: String,
        type: EntityType,
        detail: String,
        aliases: [String]
    ) -> KnowledgeSaveError? {
        // The item was removed elsewhere; there is nothing left to update.
        guard let index = knowledgeEntities.firstIndex(where: { $0.id == id }) else { return nil }

        let candidate = KnowledgeEntity(
            id: id,
            name: name,
            detail: detail,
            type: type,
            aliases: aliases,
            source: knowledgeEntities[index].source,
            createdAt: knowledgeEntities[index].createdAt
        )
        if let error = validateKnowledge(candidate) { return error }

        knowledgeEntities[index] = candidate
        showToast(text("已更新知识", "Knowledge updated"), symbol: "checkmark.circle.fill")
        return nil
    }

    func validateKnowledge(_ candidate: KnowledgeEntity) -> KnowledgeSaveError? {
        guard !candidate.normalizedKey.isEmpty else { return .emptyName }
        if let existing = knowledgeEntities.first(where: { $0.id != candidate.id && $0.normalizedKey == candidate.normalizedKey }) {
            return .duplicate(existingName: existing.name)
        }
        return nil
    }

    func acceptCorrection(_ id: UUID) {
        guard let index = corrections.firstIndex(where: { $0.id == id }) else { return }
        corrections[index].status = .accepted
        let record = corrections[index]
        let entity = KnowledgeEntity(name: record.corrected, type: .term, aliases: [record.raw], source: .correction)
        if let entityIndex = knowledgeEntities.firstIndex(where: { $0.normalizedKey == entity.normalizedKey }) {
            if !knowledgeEntities[entityIndex].aliases.contains(record.raw) { knowledgeEntities[entityIndex].aliases.append(record.raw) }
        } else {
            knowledgeEntities.append(entity)
        }
    }

    func ignoreCorrection(_ id: UUID) {
        if let index = corrections.firstIndex(where: { $0.id == id }) { corrections[index].status = .ignored }
    }

    func clearSessions() {
        sessions.removeAll()
        // Also forget turns picked up by an Agent that is still listening.
        activeAgentSessions = []
        contextItems.removeAll { $0.kind == .session }
    }

    /// Commits pending edits, then tests the saved credentials.
    func testQwenConnection(_ draft: QwenCredentialsDraft) async {
        guard connectionState != .testing, commitQwenCredentials(draft), !apiKey.isEmpty else { return }
        await runConnectionTest()
    }

    /// Saves whatever changed in the typed credentials. A Keychain failure shows in the connection status.
    @discardableResult
    func commitQwenCredentials(_ draft: QwenCredentialsDraft) -> Bool {
        let workspaceID = draft.workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if workspaceID != qwenWorkspaceID { qwenWorkspaceID = workspaceID }
        let key = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key != apiKey else { return true }
        do {
            try saveAPIKey(key)
            return true
        } catch {
            connectionState = .failed(localizedError(error))
            return false
        }
    }

    private func runConnectionTest() async {
        let key = apiKey
        let tested = configuration
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
        connectionState = apiKey == key && configuration == tested ? result : .idle
    }

    func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { try keychain.remove(Keys.apiKey) }
        else { try keychain.set(trimmed, for: Keys.apiKey) }
        apiKey = trimmed
        invalidateConnectionTest()
    }

    func playAudio(for entry: HistoryEntry) async throws -> Data {
        guard let filename = entry.audioFilename else { throw LocalStoreError.invalidAudioFilename }
        return try await store.audio(named: filename)
    }

    func retryDictation(_ id: UUID) async {
        guard let index = historyEntries.firstIndex(where: { $0.id == id }),
              historyEntries[index].canRetryTranscription,
              let filename = historyEntries[index].audioFilename else { return }
        guard !apiKey.isEmpty else {
            showToast(localizedError(QwenError.missingConfiguration), symbol: "key.fill")
            return
        }
        historyEntries[index].status = .processing
        historyEntries[index].errorMessage = nil
        do {
            let wav = try await store.audio(named: filename)
            let result = try await reasoningClient.transcribeAudio(
                apiKey: apiKey,
                configuration: configuration,
                wav: wav,
                recognitionLanguage: recognitionLanguage,
                numberFormat: dictationNumberFormat,
                cleanup: dictationCleanup,
                knowledgePrompt: renderKnowledgePrompt(.transcription)
            )
            let cleaned = try SpeechDisfluencyCleaner.dictation(result, mode: dictationCleanup)
            updateHistory(id, input: cleaned, output: cleaned, status: .completed)
            showToast(text("已重新识别", "Transcribed again"), symbol: "checkmark")
        } catch {
            updateHistory(id, status: .failed, errorMessage: localizedError(error))
        }
    }

    func copyHistoryOutput(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast(self.text("已复制", "Copied"), symbol: "doc.on.doc")
    }

    func toggleHistoryStar(_ id: UUID) {
        guard let index = historyEntries.firstIndex(where: { $0.id == id }) else { return }
        historyEntries[index].isStarred.toggle()
    }

    func deleteHistoryEntry(_ id: UUID) {
        removeHistory { $0.id == id }
    }

    func clearHistory(keepingStarred: Bool) {
        removeHistory { !keepingStarred || !$0.isStarred }
        showToast(
            keepingStarred
                ? text("已清空历史，星标记录已保留", "History cleared. Starred items were kept.")
                : text("已清空历史", "History cleared"),
            symbol: "trash"
        )
    }

    func dismissLocalDataIssue() { localDataIssue = nil }

    func dismissLegacyDataNotice() {
        legacyDataURL = nil
        defaults.set(true, forKey: Keys.legacyDataNoticeDismissed)
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
        if !didCompleteOnboarding { pendingSetupSteps = [.permissions, .qwenSetup] }
        selectedDomains = domains
        didCompleteOnboarding = true
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
        setupProgress?.isLastStep == false ? text("继续", "Continue") : text("完成", "Done")
    }

    /// Secondary button of a setup sheet that leaves the step unfinished.
    var setupSkipTitle: String {
        setupProgress == nil ? text("以后再说", "Not Now") : text("跳过", "Skip")
    }

    private func isSetupStepNeeded(_ step: AppSheet) -> Bool {
        switch step {
        case .onboarding:
            return false
        case .permissions:
            systemPermissions.refresh()
            return !systemPermissions.allRequiredPermissionsGranted
        case .qwenSetup:
            return apiKey.isEmpty
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
                text("无法更新登录项，请在“系统设置 › 通用 › 登录项”中检查", "Couldn’t update Login Items. Check System Settings › General › Login Items."),
                symbol: "exclamationmark.triangle.fill"
            )
        }
    }
    func setGlobalShortcutsPaused(_ paused: Bool) { shortcutController?.setHotKeysPaused(paused) }
    private func saveGlobalShortcut(_ shortcut: GlobalShortcut?, forKey key: String) {
        defaults.set(shortcut?.storageValue ?? "", forKey: key)
        shortcutController?.reloadHotKeys()
    }
    func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
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
            showOverlayFeedback(text("请先允许 SayKuku 使用麦克风", "Allow microphone access first"), symbol: "mic.slash", duration: .seconds(4))
            showPermissionGuide()
            showMainWindow()
            return
        }
        guard !apiKey.isEmpty else {
            let message = localizedError(QwenError.missingConfiguration)
            showOverlayFeedback(message, symbol: "key.fill", duration: .seconds(4))
            showSettings(section: .qwen)
            showToast(message, symbol: "key.fill")
            return
        }
        do {
            let snapshot = try textInteraction.captureTarget(requiringWindow: mode == .dictation)
            overlayController?.anchor(to: snapshot)
            guard !snapshot.isSensitive else { throw TextInteractionError.sensitiveTarget }
            targetSnapshot = snapshot
            liveTranscript = ""
            inputLevel = 0
            pendingCopyText = ""
            activeAgentSessions = []
            if mode == .agent {
                let conversation = continuousConversation
                    ? AgentSession.conversation(in: sessions, app: snapshot.bundleID)
                    : []
                activeAgentSessions = conversation
                contextItems = ContextCollector.collect(
                    snapshot: snapshot,
                    selectedTextAllowed: selectedTextAllowed,
                    currentAppAllowed: currentAppAllowed,
                    windowTitleAllowed: windowTitleAllowed,
                    clipboardAllowed: clipboardAllowed,
                    browserPageAllowed: browserPageAllowed,
                    session: conversation.last,
                    domains: selectedDomains,
                    knowledge: knowledgeEntities,
                    isChineseUI: usesChineseUI
                )
                if let lastVerifiedWrite, lastVerifiedWrite.isRecent,
                   let expected = lastVerifiedWrite.expectedValue,
                   snapshot.valueBefore == expected,
                   textInteraction.currentValue(of: lastVerifiedWrite.target) == expected {
                    contextItems.append(ContextCollector.textItem(
                        kind: .previousOutput,
                        symbol: "arrow.uturn.backward",
                        title: text("上次输入", "Last insertion"),
                        value: lastVerifiedWrite.text,
                        limit: ContextCollector.textLimit,
                        isChineseUI: usesChineseUI
                    ))
                }
                agentCommand = text("正在听…", "Listening…")
                dictationPhase = .idle
                agentPhase = .listening
            } else {
                agentPhase = .hidden
                dictationPhase = .idle
            }

            // Realtime needs a workspace ID; without one the full recording goes to batch recognition.
            if mode == .dictation && configuration.realtimeURL != nil {
                let generation = workflowGeneration
                let (stream, continuation) = AsyncStream<Data>.makeStream()
                chunkContinuation = continuation
                try startAudioCapture(for: mode) { continuation.yield($0) }
                withAnimation(Motion.spring) { dictationPhase = .listening }
                let shouldAutoStop = autoStop
                let selectedRecognitionLanguage = recognitionLanguage
                let selectedNumberFormat = dictationNumberFormat
                let selectedCleanup = dictationCleanup
                let knowledgePrompt = renderKnowledgePrompt(.transcription)
                let realtimeSession = UUID()
                realtimeSessionID = realtimeSession
                uploadTask = Task { [weak self, realtimeClient, apiKey, configuration, selectedRecognitionLanguage, selectedNumberFormat, selectedCleanup, knowledgePrompt] in
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
                        knowledgePrompt: knowledgePrompt
                    )
                    for await chunk in stream { try await realtimeClient.append(chunk, session: realtimeSession) }
                }
            } else {
                try startAudioCapture(for: mode) { _ in }
                if mode == .dictation { withAnimation(Motion.spring) { dictationPhase = .listening } }
            }
            // Both paths are listening with the engine running by now.
            playSoundCue(.start)
            scheduleRecordingLimit(for: mode)
        } catch {
            handleWorkflowError(error, agent: mode == .agent)
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
                        self.text("\(seconds) 秒后自动结束录音", "Recording stops in \(seconds) seconds"),
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
        guard soundCuesEnabled else { return }
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

    private func startAudioCapture(for mode: VoiceWorkflowMode, onChunk: @escaping @Sendable (Data) -> Void) throws {
        let generation = workflowGeneration
        try audioCapture.start(
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
                          self.dictationPhase == .listening || self.agentPhase == .listening else { return }
                    self.finishListening(for: mode)
                    self.showOverlayFeedback(
                        self.text("音频设备已切换，录音已结束", "Audio device changed. Recording stopped."),
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
                recording, upload: upload, realtimeSession: realtimeSession, generation: generation
            )
            try Task.checkCancellation()
            guard generation == workflowGeneration else { throw CancellationError() }
            guard !transcript.isEmpty else { throw QwenError.invalidResponse }
            guard let snapshot else { throw TextInteractionError.targetChanged }
            let raw = DictationTextJoiner.join(transcript, to: snapshot)
            updateHistory(historyID, input: transcript, output: raw)
            do {
                let outcome = try await textInteraction.write(raw, to: snapshot)
                updateHistory(historyID, status: .completed)
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
                updateHistory(historyID, status: .completed)
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
            updateHistory(historyID, status: .cancelled)
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
                knowledgePrompt: knowledgePrompt
            )
            try Task.checkCancellation()
            guard generation == workflowGeneration else { throw CancellationError() }
            guard let transcript = response.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !transcript.isEmpty else { throw QwenError.invalidResponse }
            let command = SpeechDisfluencyCleaner.clean(transcript, mode: .light)
            guard let snapshot else { throw TextInteractionError.targetChanged }
            updateHistory(historyID, input: command)
            agentCommand = response.intent ?? response.action.title(isChineseUI: usesChineseUI)
            withAnimation(Motion.panel) { agentPhase = .processing }
            await executeAgent(
                response, snapshot: snapshot, context: context,
                command: command, historyID: historyID, generation: generation
            )
        } catch is CancellationError {
            updateHistory(historyID, status: .cancelled)
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
        realtimeSession: UUID, generation: Int
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
                return try SpeechDisfluencyCleaner.dictation(result, mode: dictationCleanup)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                guard generation == workflowGeneration else { throw CancellationError() }
                // Batch recognition only helps with transport problems; configuration errors would fail twice.
                guard QwenError.allowsBatchFallback(after: error) else { throw error }
                await realtimeClient.cancel(session: realtimeSession)
            }
        }
        let result = try await reasoningClient.transcribeAudio(
            apiKey: apiKey,
            configuration: configuration,
            wav: recording.wav,
            recognitionLanguage: recognitionLanguage,
            numberFormat: dictationNumberFormat,
            cleanup: dictationCleanup,
            knowledgePrompt: renderKnowledgePrompt(.transcription)
        )
        return try SpeechDisfluencyCleaner.dictation(result, mode: dictationCleanup)
    }

    /// Saved knowledge and domain presets for a prompt; the Agent leaves out whichever the user removed from its context.
    private func renderKnowledgePrompt(
        _ purpose: KnowledgePrompt.Purpose, includesKnowledge: Bool = true, includesDomains: Bool = true
    ) -> String {
        KnowledgePrompt.render(
            entities: includesKnowledge ? knowledgeEntities : [],
            domains: includesDomains ? selectedDomains : [],
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
                guard let text = response.output, !text.isEmpty else { throw QwenError.invalidResponse }
                if automaticAgentWriteBack, !AgentActionExecutor.replacesClippedText(response, context: context) {
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
                        updateHistory(historyID, input: command, output: text, status: .completed)
                        try Task.checkCancellation()
                        guard generation == workflowGeneration else { throw CancellationError() }
                        lastVerifiedWrite = outcome == .verified ? VerifiedWrite(target: writeTarget, text: text) : nil
                        resultCanUndo = outcome == .verified
                    } catch is TextInteractionError {
                        needsCopyFallback = true
                    }
                } else {
                    needsCopyFallback = true
                }
                output = text
            } else if response.action == .answer {
                guard let text = response.output, !text.isEmpty else { throw QwenError.invalidResponse }
                output = text
            } else if AgentActionExecutor.needsConfirmation(response, context: context) {
                // Checked now so the card never offers an action that cannot run.
                try AgentActionExecutor.validate(response, engine: searchEngine)
                actionToConfirm = response
                output = response.url ?? response.query ?? response.shortcutName ?? ""
            } else {
                resultCanUndo = false
                try await AgentActionExecutor.execute(response, engine: searchEngine)
                output = response.url ?? response.query ?? response.shortcutName ?? ""
            }
            updateHistory(historyID, input: command, output: output, status: .completed)
            if continuousConversation {
                sessions = AgentSession.appending(AgentSession(
                    app: snapshot.bundleID,
                    contextSummary: QwenReasoningClient.sessionContextSummary(context: context, response: response),
                    userCommand: command,
                    response: output,
                    expiresAt: .now.addingTimeInterval(30 * 60)
                ), to: sessions)
            }
            // A write or action can finish after the user dismissed this workflow or started a new one.
            guard generation == workflowGeneration else { return }
            if needsCopyFallback {
                presentCopyFallback(output, agent: true, copyImmediately: automaticAgentWriteBack)
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
            updateHistory(historyID, status: .cancelled)
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
            updateHistory(historyID, status: .cancelled)
            return
        }
        updateHistory(historyID, status: .failed, errorMessage: localizedError(error))
        handleWorkflowError(error, agent: agent)
    }

    private func beginHistoryEntry(mode: HistoryMode, recording: AudioCapture.Recording) -> UUID? {
        guard historyRetention != .off, let snapshot = targetSnapshot, !snapshot.isSensitive else { return nil }
        let id = UUID()
        historyEntries.insert(HistoryEntry(
            id: id, mode: mode, app: snapshot.appName, durationSeconds: recording.duration,
            input: "", output: "", status: .processing
        ), at: 0)
        cleanExpiredHistory()
        return id
    }

    private func persistHistoryAudio(_ recording: AudioCapture.Recording, historyID: UUID?) async {
        guard let historyID else { return }
        var saveFailed = false
        if storeVoiceAudio, !recording.wav.isEmpty {
            do {
                let filename = try await store.saveAudio(recording.wav, id: historyID)
                if historyEntries.contains(where: { $0.id == historyID }) {
                    updateHistory(historyID, audioFilename: filename)
                } else {
                    // The entry was deleted while its recording was being saved.
                    try? await store.removeAudio(named: filename)
                }
            } catch {
                saveFailed = true
            }
        }
        do {
            try await persistCurrentState()
        } catch {
            saveFailed = true
        }
        // The user is usually in another app, where only the overlay is visible.
        if saveFailed {
            showOverlayFeedback(
                text("这条历史没能保存，识别不受影响", "Couldn’t save this to History. Transcription will continue."),
                symbol: "exclamationmark.triangle"
            )
        }
    }

    private func updateHistory(
        _ id: UUID?, input: String? = nil, output: String? = nil,
        audioFilename: String? = nil, status: HistoryStatus? = nil, errorMessage: String? = nil
    ) {
        guard let id, let index = historyEntries.firstIndex(where: { $0.id == id }) else { return }
        if let input { historyEntries[index].input = input }
        if let output { historyEntries[index].output = output }
        if let audioFilename { historyEntries[index].audioFilename = audioFilename }
        if let status, historyEntries[index].status == .processing {
            historyEntries[index].status = status
            historyEntries[index].errorMessage = errorMessage
        } else if let errorMessage {
            historyEntries[index].errorMessage = errorMessage
        }
    }

    private func cancelWorkflow() {
        workflowGeneration += 1
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
        if (error as? QwenError) == .noSpeech {
            showOverlayFeedback(message, symbol: "waveform.slash")
            return
        }
        // The overlay is the only surface visible from other apps; the toast only helps inside SayKuku.
        showOverlayFeedback(message, symbol: "exclamationmark", duration: .seconds(4))
        if Self.needsSettings(error) {
            showSettings(section: .qwen)
            // The overlay already says what went wrong; the toast explains why Settings opened.
            showToast(text("已打开“设置 › Qwen 连接”", "Opened Settings › Qwen Connection"), symbol: "gearshape")
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

    private func showOverlayFeedback(_ message: String, symbol: String, duration: Duration = .seconds(2.4)) {
        overlayFeedbackGeneration += 1
        let generation = overlayFeedbackGeneration
        overlayErrorSymbol = symbol
        overlayError = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard self?.overlayFeedbackGeneration == generation else { return }
            withAnimation(Motion.snappy) { self?.overlayError = nil }
        }
    }

    private func observeCorrection(writtenText: String, snapshot: TextTargetSnapshot, writeID: UUID) {
        guard learnFromCorrections, let before = snapshot.valueBefore, let range = snapshot.selectedRange else { return }
        let source = before as NSString
        guard range.location >= 0, range.length >= 0, NSMaxRange(NSRange(location: range.location, length: range.length)) <= source.length else { return }
        let expected = source.replacingCharacters(in: NSRange(location: range.location, length: range.length), with: writtenText)
        let writtenRange = range.location..<(range.location + (writtenText as NSString).length)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.lastVerifiedWrite?.id == writeID,
                  let actual = self.textInteraction.currentValue(of: snapshot),
                  let change = CorrectionExtractor.extract(expected: expected, actual: actual, writtenRange: writtenRange) else { return }
            if let index = self.corrections.firstIndex(where: { $0.raw == change.before && $0.corrected == change.after }) {
                self.corrections[index].count += 1
                self.corrections[index].lastSeenAt = .now
                self.corrections[index].lastApp = snapshot.appName
            } else {
                self.corrections.append(CorrectionRecord(raw: change.before, corrected: change.after, lastApp: snapshot.appName))
            }
        }
    }

    func localizedError(_ error: Error) -> String {
        if let textError = error as? TextInteractionError {
            switch textError {
            case .accessibilityRequired:
                return text("请先允许 SayKuku 使用辅助功能", "Allow Accessibility access for SayKuku first")
            case .noFocusedElement:
                return text("请先点一下要输入文字的位置", "Click where you want to type first")
            case .sensitiveTarget:
                return text("为保护隐私，SayKuku 不在密码框和密码管理器中使用", "SayKuku doesn’t work in password fields or password managers.")
            case .targetChanged:
                return text("输入位置变了，请回到输入框再试一次", "The text field changed. Click back into it and try again.")
            case .writeFailed:
                return text("这个 App 没有接收文字，请重试", "This app didn’t accept the text. Try again.")
            }
        }
        if let qwenError = error as? QwenError {
            switch qwenError {
            case .missingConfiguration:
                return text("请先添加 Qwen API Key", "Add your Qwen API Key first")
            case .invalidEndpoint:
                return text(
                    "无法连接 Qwen，请在“设置 › Qwen 连接”中检查地域和业务空间 ID",
                    "Couldn’t reach Qwen. Check the Region and Workspace ID in Settings › Qwen Connection."
                )
            case .invalidResponse:
                return text("没有拿到结果，请重试", "Couldn’t get a result. Try again.")
            case .noSpeech:
                return text("没有听清，请再说一次", "Didn’t catch that. Try again.")
            case .server(let status, _):
                if status == 401 || status == 403 {
                    return text("API Key 无效或没有权限，请在“设置 › Qwen 连接”中检查", "Your API Key was rejected. Check Settings › Qwen Connection.")
                }
                if status == 429 {
                    return text("请求太频繁，请稍后再试", "Too many requests. Try again in a moment.")
                }
                if status == 400 {
                    // Often content inspection or unreadable audio, so Settings is only the last resort.
                    return text(
                        "Qwen 没有接受这次请求，请重试，或在“设置 › Qwen 连接”中检查模型",
                        "Qwen rejected this request. Try again, or check the model in Settings › Qwen Connection."
                    )
                }
                return text("Qwen 暂时无法处理，请重试", "Qwen couldn’t handle the request. Try again.")
            case .protocolError:
                return text("与 Qwen 的连接中断了，请重试", "Lost connection to Qwen. Try again.")
            case .timeout:
                return text("Qwen 响应超时，请重试", "Qwen took too long to respond. Try again.")
            case .recordingTooLong:
                return text("录音太长了，请分成几段说", "That recording is too long. Try shorter parts.")
            }
        }
        if error is AudioCaptureError {
            return text("无法使用麦克风，请检查输入设备和麦克风权限", "Couldn’t use the microphone. Check your input device and microphone access.")
        }
        if error is LocalStoreError {
            return text("无法读取本机数据，请重启 SayKuku 后重试", "Couldn’t read local data. Restart SayKuku and try again.")
        }
        if error is SecureStorageError {
            return text("无法保存 API Key，请检查这台 Mac 的钥匙串", "Couldn’t save the API Key. Check Keychain on this Mac.")
        }
        if error is URLError {
            return text("无法连接网络，请检查网络后重试", "Couldn’t connect. Check your network and try again.")
        }
        if let actionError = error as? AgentActionError {
            switch actionError {
            case .shortcutFailed:
                return text("快捷指令运行失败，请在“快捷指令”App 中检查", "Couldn’t run the shortcut. Check it in the Shortcuts app.")
            case .shortcutTimedOut:
                return text("快捷指令超过 1 分钟没有完成，已停止", "The shortcut took over a minute, so it was stopped.")
            }
        }
        return text("出了点问题，请重试", "Something went wrong. Try again.")
    }

    /// Earlier builds saved these placeholders as detail; clear them so they stay out of the UI and prompts.
    private static let legacyPlaceholderDetails: Set<String> = ["手动添加", "Added manually", "来自纠正记忆", "From correction memory"]

    func loadStoredData() async {
        guard !didStartLoading else { return }
        didStartLoading = true
        localDataIssue = await store.dataIssue
        if !defaults.bool(forKey: Keys.legacyDataNoticeDismissed) {
            legacyDataURL = await store.legacyEncryptedDataURL()
        }
        let snapshot: LocalStore.Snapshot
        do {
            snapshot = try await store.load()
        } catch {
            showToast(
                text("无法读取本机数据，新的更改暂时不会保存，详情见“历史”", "Couldn’t read local data, so new changes won’t be saved. See History for details."),
                symbol: "exclamationmark.triangle.fill"
            )
            return
        }
        historyEntries = Self.merging(historyEntries, Self.recoveringInterruptedHistory(
            snapshot.history,
            message: text("SayKuku 退出时还没处理完", "SayKuku quit before this finished")
        )).sorted { $0.createdAt > $1.createdAt }
        knowledgeEntities = Self.merging(knowledgeEntities, snapshot.entities.map { entity in
            var entity = entity
            if Self.legacyPlaceholderDetails.contains(entity.detail) { entity.detail = "" }
            return entity
        })
        corrections = Self.merging(corrections, snapshot.corrections)
        sessions = Self.merging(sessions, snapshot.sessions.filter { $0.expiresAt > .now })
        cleanExpiredHistory()
        // Saving before every array is in place would replace the stored data with part of it.
        isLoaded = true
        migrateLegacyCustomTerms()
        schedulePersistence()
        if localDataIssue != nil {
            showToast(
                text("读取本机数据时出了问题，原文件已备份，详情见“历史”", "There was a problem reading local data. The original file was backed up. See History for details."),
                symbol: "exclamationmark.triangle.fill"
            )
        }
    }

    /// Earlier builds kept custom words in defaults; they now live in Knowledge as terms.
    /// Runs once Knowledge has loaded, so words already saved there are skipped as duplicates.
    private func migrateLegacyCustomTerms() {
        guard let terms = defaults.stringArray(forKey: Keys.legacyCustomTerms) else { return }
        for term in terms { _ = insertKnowledge(KnowledgeEntity(name: term, type: .term)) }
        defaults.removeObject(forKey: Keys.legacyCustomTerms)
    }

    /// Keeps records added while loading; stored records fill in the rest.
    private static func merging<Record: Identifiable>(_ current: [Record], _ stored: [Record]) -> [Record] {
        let currentIDs = Set(current.map(\.id))
        return current + stored.filter { !currentIDs.contains($0.id) }
    }

    /// Entries still processing at launch were cut off by a quit or crash; keep their audio so they can be retried.
    nonisolated static func recoveringInterruptedHistory(_ entries: [HistoryEntry], message: String) -> [HistoryEntry] {
        entries.map { entry in
            guard entry.status == .processing else { return entry }
            var recovered = entry
            recovered.status = .failed
            recovered.errorMessage = message
            return recovered
        }
    }

    private func cleanExpiredHistory() {
        guard let days = historyRetention.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return }
        removeHistory { !$0.isStarred && $0.createdAt < cutoff }
    }

    /// Removes matching entries and deletes their recordings.
    private func removeHistory(where shouldRemove: (HistoryEntry) -> Bool) {
        let removed = historyEntries.filter(shouldRemove)
        guard !removed.isEmpty else { return }
        historyEntries.removeAll(where: shouldRemove)
        let filenames = removed.compactMap(\.audioFilename)
        guard !filenames.isEmpty else { return }
        Task { [store] in
            for filename in filenames { try? await store.removeAudio(named: filename) }
        }
    }

    /// Coalesces a burst of changes, such as the several updates one dictation makes, into one write.
    private func schedulePersistence() {
        guard isLoaded else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self, persistenceDelay] in
            do { try await Task.sleep(for: persistenceDelay) } catch { return }
            await self?.flushPersistence()
        }
    }

    /// Writes pending changes now and reports whether they were saved. Quitting waits for this.
    @discardableResult
    func flushPersistence() async -> Bool {
        do {
            try await persistCurrentState()
            return true
        } catch {
            showToast(
                text("本机数据没能保存，最近的更改可能会丢失，请检查磁盘空间", "Couldn’t save your data, so recent changes may be lost. Check your available storage."),
                symbol: "exclamationmark.triangle.fill"
            )
            return false
        }
    }

    private func persistCurrentState() async throws {
        persistenceTask?.cancel()
        persistenceTask = nil
        guard let snapshot = nextPersistedSnapshot() else { return }
        try await store.replace(snapshot.value, generation: snapshot.generation)
    }

    /// The state to save, numbered so an older write never replaces a newer one; nil until stored data has loaded.
    private func nextPersistedSnapshot() -> (value: LocalStore.Snapshot, generation: Int)? {
        guard isLoaded else { return nil }
        persistenceGeneration += 1
        let value = LocalStore.Snapshot(
            history: historyEntries, entities: knowledgeEntities, corrections: corrections, sessions: sessions
        )
        return (value, persistenceGeneration)
    }

    private func loadSettings() {
        if let raw = defaults.string(forKey: Keys.inputMode), let value = InputMode(rawValue: raw) { inputMode = value }
        if let raw = defaults.string(forKey: Keys.language), let value = AppLanguage(rawValue: raw) { appLanguage = value }
        if let raw = defaults.string(forKey: Keys.recognitionLanguage),
           let value = RecognitionLanguage(rawValue: raw) { recognitionLanguage = value }
        if let raw = defaults.string(forKey: Keys.dictationNumberFormat),
           let value = DictationNumberFormat(rawValue: raw) { dictationNumberFormat = value }
        if let raw = defaults.string(forKey: Keys.dictationCleanup),
           let value = DictationCleanup(rawValue: raw) { dictationCleanup = value }
        selectedDomains = Set((defaults.stringArray(forKey: Keys.selectedDomains) ?? []).compactMap(DomainPreset.init(rawValue:)))
        didCompleteOnboarding = defaults.bool(forKey: Keys.didCompleteOnboarding)
        if let raw = defaults.string(forKey: Keys.historyRetention), let value = HistoryRetention(rawValue: raw) { historyRetention = value }
        if let raw = defaults.string(forKey: Keys.qwenRegion), let value = QwenRegion(rawValue: raw) { qwenRegion = value }
        qwenWorkspaceID = defaults.string(forKey: Keys.qwenWorkspace) ?? ""
        // One-time move from the old 3.5 default to 3.8; afterwards an explicit 3.5 choice sticks.
        realtimeModel = QwenModelCatalog.realtimeModel(
            stored: defaults.string(forKey: Keys.realtimeModel),
            upgradesPreviousDefault: !defaults.bool(forKey: Keys.realtimeModelUpgraded)
        )
        defaults.set(true, forKey: Keys.realtimeModelUpgraded)
        reasoningModel = QwenModelCatalog.reasoningModel(stored: defaults.string(forKey: Keys.reasoningModel))
        storedSearchEngine = defaults.string(forKey: Keys.searchEngine).flatMap(SearchEngine.init(rawValue:))
        autoStop = storedBool(Keys.autoStop, default: false)
        continuousConversation = storedBool(Keys.continuousConversation, default: true)
        automaticAgentWriteBack = storedBool(Keys.automaticAgentWriteBack, default: true)
        learnFromCorrections = storedBool(Keys.learnCorrections, default: true)
        soundCuesEnabled = storedBool(Keys.soundCues, default: true)
        selectedTextAllowed = storedBool(Keys.selectedText, default: true)
        currentAppAllowed = storedBool(Keys.currentApp, default: true)
        windowTitleAllowed = storedBool(Keys.windowTitle, default: true)
        clipboardAllowed = defaults.bool(forKey: Keys.clipboard)
        browserPageAllowed = defaults.bool(forKey: Keys.browserPage)
        storeVoiceAudio = storedBool(Keys.storeVoiceAudio, default: true)
        showInMenuBar = storedBool(Keys.showInMenuBar, default: true)
        hideDockIconAfterMainWindowCloses = storedBool(Keys.hideDockIconAfterMainWindowCloses, default: false)
        // Earlier builds hard-coded ⇧⌘D / ⇧⌘A without saving them, so upgrades start from the new defaults.
        if let raw = defaults.string(forKey: Keys.voiceInputShortcut) {
            voiceInputShortcut = GlobalShortcut.restored(from: raw, fallback: .defaultVoiceInput)
        }
        if let raw = defaults.string(forKey: Keys.voiceAgentShortcut) {
            voiceAgentShortcut = GlobalShortcut.restored(from: raw, fallback: .defaultVoiceAgent)
        }
    }

    /// The saved flag, or `fallback` when it was never saved.
    private func storedBool(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private enum Keys {
        static let inputMode = "inputMode", language = "appLanguage", autoStop = "autoStop"
        static let recognitionLanguage = "dictation.recognitionLanguage", dictationNumberFormat = "dictation.numberFormat"
        static let dictationCleanup = "dictation.cleanup", soundCues = "voice.soundCues"
        static let selectedDomains = "dictation.selectedDomains", legacyCustomTerms = "dictation.customDomainTerms"
        static let didCompleteOnboarding = "onboarding.completed"
        static let continuousConversation = "continuousConversation", learnCorrections = "learnFromCorrections"
        static let automaticAgentWriteBack = "agent.automaticWriteBack", searchEngine = "agent.searchEngine"
        static let selectedText = "privacy.selectedText", currentApp = "privacy.currentApp", windowTitle = "privacy.windowTitle"
        static let clipboard = "privacy.clipboard", browserPage = "privacy.browserPage"
        static let historyRetention = "historyRetention", storeVoiceAudio = "storeVoiceAudio", showInMenuBar = "showInMenuBar"
        static let hideDockIconAfterMainWindowCloses = "hideDockIconAfterMainWindowCloses"
        static let legacyDataNoticeDismissed = "history.legacyDataNoticeDismissed"
        static let qwenRegion = "qwen.region", qwenWorkspace = "qwen.workspace", realtimeModel = "qwen.realtimeModel"
        static let reasoningModel = "qwen.reasoningModel", apiKey = "qwen.apiKey"
        static let voiceInputShortcut = "shortcuts.voiceInput", voiceAgentShortcut = "shortcuts.voiceAgent"
        static let realtimeModelUpgraded = "qwen.realtimeModelUpgradedToQwen38"
    }

    private func presentStartupExperienceIfNeeded() {
        if didCompleteOnboarding {
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

    @MainActor func title(_ appState: AppState) -> String {
        appState.text("第 \(step) 步，共 \(total) 步", "Step \(step) of \(total)")
    }
}

enum InputMode: String, CaseIterable, Identifiable {
    case hold = "按住 Fn", tap = "单击 Fn"
    var id: String { rawValue }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, chinese, english
    var id: String { rawValue }
    func title(isChineseUI: Bool) -> String {
        switch self {
        case .system: isChineseUI ? "跟随系统" : "System Default"
        case .chinese: "简体中文"
        case .english: "English"
        }
    }
}

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let symbol: String
}
