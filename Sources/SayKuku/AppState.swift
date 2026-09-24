import AppKit
import AVFoundation
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppState {
    enum Destination: String, CaseIterable, Identifiable {
        case home = "Home", history = "History", knowledge = "Knowledge", memory = "Memory", settings = "Settings"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .home: "house"
            case .history: "clock.arrow.circlepath"
            case .knowledge: "books.vertical"
            case .memory: "sparkles.rectangle.stack"
            case .settings: "gearshape"
            }
        }
        @MainActor func title(_ appState: AppState) -> String {
            switch self {
            case .home: appState.text("首页", "Home")
            case .history: appState.text("历史", "History")
            case .knowledge: appState.text("知识", "Knowledge")
            case .memory: appState.text("记忆", "Memory")
            case .settings: appState.text("设置", "Settings")
            }
        }
    }

    enum DictationPhase: Equatable { case idle, listening, processing, success, copyReady }
    enum AgentPhase: Equatable { case hidden, listening, transcribing, processing, result, copyReady, answerReady }
    enum ConnectionState: Equatable { case idle, testing, connected(milliseconds: Int), failed(String) }

    enum ShortcutStatus: Equatable {
        case starting, ready, accessibilityRequired, hotKeyConflict
        var symbol: String {
            switch self {
            case .starting: "clock"
            case .ready: "checkmark.circle"
            case .accessibilityRequired, .hotKeyConflict: "exclamationmark.triangle"
            }
        }
        @MainActor func title(_ appState: AppState) -> String {
            switch self {
            case .starting: appState.text("正在启动快捷键…", "Starting shortcuts…")
            case .ready: appState.text("Fn 与全局快捷键已就绪", "Fn and global shortcuts ready")
            case .accessibilityRequired: appState.text("全局快捷键可用 · Fn 需要辅助功能权限", "Global shortcuts ready · Fn needs Accessibility")
            case .hotKeyConflict: appState.text("快捷键被其他 App 占用，请检查冲突", "Shortcuts are in use by another app; check for conflicts")
            }
        }
    }

    var destination: Destination = .home
    var appLanguage: AppLanguage = .system { didSet { defaults.set(appLanguage.rawValue, forKey: Keys.language) } }
    var dictationPhase: DictationPhase = .idle { didSet { overlayController?.refresh() } }
    var agentPhase: AgentPhase = .hidden { didSet { overlayController?.refresh() } }
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
    var customDomainTerms: [String] = [] {
        didSet { defaults.set(customDomainTerms, forKey: Keys.customDomainTerms) }
    }
    var didCompleteOnboarding = false {
        didSet { defaults.set(didCompleteOnboarding, forKey: Keys.didCompleteOnboarding) }
    }
    var continuousConversation = true { didSet { defaults.set(continuousConversation, forKey: Keys.continuousConversation) } }
    var automaticAgentWriteBack = true {
        didSet { defaults.set(automaticAgentWriteBack, forKey: Keys.automaticAgentWriteBack) }
    }
    var learnFromCorrections = true { didSet { defaults.set(learnFromCorrections, forKey: Keys.learnCorrections) } }
    var selectedTextAllowed = true { didSet { defaults.set(selectedTextAllowed, forKey: Keys.selectedText) } }
    var currentAppAllowed = true { didSet { defaults.set(currentAppAllowed, forKey: Keys.currentApp) } }
    var windowTitleAllowed = true { didSet { defaults.set(windowTitleAllowed, forKey: Keys.windowTitle) } }
    var clipboardAllowed = false { didSet { defaults.set(clipboardAllowed, forKey: Keys.clipboard) } }
    var browserPageAllowed = false { didSet { defaults.set(browserPageAllowed, forKey: Keys.browserPage) } }
    var contextItems: [ContextItem] = []
    var agentCommand = ""
    var liveTranscript = ""
    var inputLevel = 0.0
    var pendingCopyText = ""
    var pendingAnswerText = ""
    var pendingAnswerStatus: String?
    var resultCanUndo = false
    var overlayErrorSymbol = "exclamationmark"
    var overlayError: String? { didSet { overlayController?.refresh() } }
    var toast: ToastMessage?
    var historyEntries: [HistoryEntry] = [] { didSet { schedulePersistence() } }
    var knowledgeEntities: [KnowledgeEntity] = [] { didSet { schedulePersistence() } }
    var knowledgeRelationships: [KnowledgeRelationship] = [] { didSet { schedulePersistence() } }
    var corrections: [CorrectionRecord] = [] { didSet { schedulePersistence() } }
    var sessions: [AgentSession] = [] { didSet { schedulePersistence() } }
    var historyRetention: HistoryRetention = .days30 {
        didSet { defaults.set(historyRetention.rawValue, forKey: Keys.historyRetention); cleanExpiredHistory() }
    }
    var storeVoiceAudio = true { didSet { defaults.set(storeVoiceAudio, forKey: Keys.storeVoiceAudio) } }
    private(set) var localDataIssue: LocalStore.DataIssue?
    private(set) var legacyDataURL: URL?
    var shortcutStatus: ShortcutStatus = .starting
    var presentedSheet: AppSheet?
    private(set) var showInMenuBar = true { didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) } }
    var hideDockIconAfterMainWindowCloses = false {
        didSet {
            defaults.set(hideDockIconAfterMainWindowCloses, forKey: Keys.hideDockIconAfterMainWindowCloses)
            if hideDockIconAfterMainWindowCloses { showInMenuBar = true }
        }
    }
    var launchAtLogin = false
    var qwenRegion: QwenRegion = .beijing { didSet { defaults.set(qwenRegion.rawValue, forKey: Keys.qwenRegion) } }
    var qwenWorkspaceID = "" { didSet { defaults.set(qwenWorkspaceID, forKey: Keys.qwenWorkspace) } }
    var realtimeModel = "qwen3.5-omni-flash-realtime" { didSet { defaults.set(realtimeModel, forKey: Keys.realtimeModel) } }
    var reasoningModel = "qwen3.8-omni-flash" { didSet { defaults.set(reasoningModel, forKey: Keys.reasoningModel) } }
    var apiKey = ""
    var connectionState: ConnectionState = .idle
    var knowledgeAnalysis: KnowledgeAnalysis?
    var isAnalyzingKnowledge = false
    let systemPermissions = SystemPermissionController()
    let microphoneTest = MicrophoneTestController()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let audioCapture = AudioCapture()
    @ObservationIgnored private let realtimeClient = QwenRealtimeClient()
    @ObservationIgnored private let reasoningClient = QwenReasoningClient()
    @ObservationIgnored private let textInteraction = TextInteraction()
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
    @ObservationIgnored private var didEvaluateStartupPermissions = false
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var persistenceGeneration = 0

    static let mainWindowID = "main"
    private static let dictationRecordingLimit: Duration = .seconds(600)
    /// Keeps Agent audio under `QwenReasoningClient.maximumAudioBytes`.
    private static let agentRecordingLimit: Duration = .seconds(210)
    private static let recordingLimitWarning: Duration = .seconds(15)
    private static let successDisplayDuration: Duration = .seconds(3)

    init(
        defaults: UserDefaults = .standard,
        store: LocalStore = LocalStore(),
        keychain: KeychainStore = KeychainStore()
    ) {
        self.defaults = defaults
        self.store = store
        self.keychain = keychain
        loadSettings()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        apiKey = (try? keychain.string(for: Keys.apiKey)) ?? ""
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
        withAnimation(Motion.snappy) { dictationPhase = .idle }
    }

    func finishDictation() {
        guard dictationPhase == .listening else { return }
        let recording = stopRecording()
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
        let historyID = beginHistoryEntry(mode: .agent, recording: recording)
        let snapshot = targetSnapshot
        let context = contextItems
        let conversation = activeAgentSessions
        targetSnapshot = nil
        activeAgentSessions = []
        let generation = workflowGeneration
        withAnimation(Motion.snappy) { agentPhase = .transcribing }
        workflowTask = Task { [weak self] in
            await self?.processAgentRecording(
                recording, historyID: historyID, snapshot: snapshot,
                context: context, conversation: conversation, generation: generation
            )
        }
    }

    func dismissAgent() {
        cancelWorkflow()
        withAnimation(Motion.snappy) { agentPhase = .hidden }
    }

    func cancelActiveVoiceWorkflow() {
        guard dictationPhase != .idle || agentPhase != .hidden else { return }
        cancelWorkflow()
        withAnimation(Motion.snappy) {
            dictationPhase = .idle
            agentPhase = .hidden
        }
    }

    func copyPendingText() {
        guard !pendingCopyText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(pendingCopyText, forType: .string)
    }

    var canUndoLastWrite: Bool { lastVerifiedWrite != nil }

    func undoLastWrite() async {
        guard let lastVerifiedWrite else { return }
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
                    ? text("已撤销上次写入", "Last voice insertion undone")
                    : text("已发送撤销，请检查结果", "Undo sent; check the result"),
                symbol: "arrow.uturn.backward"
            )
        } catch {
            if generation == workflowGeneration, self.lastVerifiedWrite?.id == lastVerifiedWrite.id {
                showOverlayFeedback(text("原输入已变化或应用不支持撤销", "The target changed or does not support undo"), symbol: "exclamationmark.triangle")
            }
        }
    }

    func dismissAnswer() {
        pendingAnswerText = ""
        pendingAnswerStatus = nil
        pendingAnswerTarget = nil
        agentPhase = .hidden
    }

    func copyAnswer() {
        guard !pendingAnswerText.isEmpty else { return }
        pendingCopyText = pendingAnswerText
        copyPendingText()
        pendingAnswerStatus = text("已复制回答", "Answer copied")
    }

    func insertAnswer() async {
        guard let snapshot = pendingAnswerTarget, !pendingAnswerText.isEmpty else { return }
        let answer = pendingAnswerText
        let generation = workflowGeneration
        do {
            let outcome = try await textInteraction.write(answer, to: snapshot)
            guard generation == workflowGeneration, pendingAnswerText == answer else { return }
            lastVerifiedWrite = outcome == .verified ? VerifiedWrite(target: snapshot, text: answer) : nil
            dismissAnswer()
            showOverlayFeedback(
                outcome == .verified
                    ? text("已写入回答", "Answer inserted")
                    : text("已发送写入，请检查结果", "Insertion sent; check the result"),
                symbol: "checkmark"
            )
        } catch {
            if generation == workflowGeneration, pendingAnswerText == answer {
                pendingAnswerStatus = text("输入位置已变化，可复制回答", "The target changed; copy the answer instead")
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
        var relationships: [ProposedRelationship] = []
        for chunk in KnowledgePipeline.chunks(redacted.text) {
            let extraction = try await reasoningClient.extractKnowledge(apiKey: apiKey, configuration: configuration, text: chunk)
            entities.append(contentsOf: extraction.entities)
            relationships.append(contentsOf: extraction.relationships)
        }
        return KnowledgePipeline.analyze(
            proposals: entities,
            relationships: relationships,
            existing: knowledgeEntities,
            existingRelationships: knowledgeRelationships,
            ignored: redacted.ignored
        )
    }

    func commitKnowledge(_ analysis: KnowledgeAnalysis, selectedIDs: Set<UUID>) {
        let result = KnowledgePipeline.commit(analysis: analysis, selectedIDs: selectedIDs, existing: knowledgeEntities)
        knowledgeEntities = result.entities
        let existingKeys = Set(knowledgeRelationships.map { "\($0.fromEntityID)-\($0.type.rawValue)-\($0.toEntityID)" })
        knowledgeRelationships.append(contentsOf: result.relationships.filter {
            !existingKeys.contains("\($0.fromEntityID)-\($0.type.rawValue)-\($0.toEntityID)")
        })
    }

    @discardableResult
    func addKnowledge(name: String, type: EntityType, detail: String? = nil, aliases: [String] = []) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let candidate = KnowledgeEntity(name: trimmed, detail: detail ?? "", type: type, aliases: aliases)
        guard !knowledgeEntities.contains(where: { $0.normalizedKey == candidate.normalizedKey }) else {
            showToast(text("该条目已存在", "This item already exists"), symbol: "exclamationmark.circle")
            return false
        }
        knowledgeEntities.insert(candidate, at: 0)
        showToast(text("已加入知识", "Added to Knowledge"), symbol: "checkmark.circle.fill")
        return true
    }

    @discardableResult
    func updateKnowledge(
        id: UUID,
        name: String,
        type: EntityType,
        detail: String,
        aliases: [String]
    ) -> Bool {
        guard let index = knowledgeEntities.firstIndex(where: { $0.id == id }) else { return false }

        let candidate = KnowledgeEntity(
            id: id,
            name: name,
            detail: detail,
            type: type,
            aliases: aliases,
            source: knowledgeEntities[index].source,
            createdAt: knowledgeEntities[index].createdAt
        )
        guard !candidate.name.isEmpty, !candidate.normalizedKey.isEmpty else {
            showToast(text("名称不能为空", "Name cannot be empty"), symbol: "exclamationmark.circle")
            return false
        }
        guard !knowledgeEntities.contains(where: { $0.id != id && $0.normalizedKey == candidate.normalizedKey }) else {
            showToast(text("该名称已存在", "This name already exists"), symbol: "exclamationmark.circle")
            return false
        }

        knowledgeEntities[index] = candidate
        showToast(text("已更新知识", "Knowledge updated"), symbol: "checkmark.circle.fill")
        return true
    }

    func suggestEntityType(for name: String) async throws -> EntityType {
        let result = try await reasoningClient.extractKnowledge(apiKey: apiKey, configuration: configuration, text: name)
        return result.entities.first?.type ?? .unknown
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
        activeAgentSession = nil
    }

    func testQwenConnection() async {
        connectionState = .testing
        let realtimeSession = UUID()
        do {
            try saveAPIKey(apiKey)
            let started = Date.now
            try await realtimeClient.connect(
                session: realtimeSession,
                apiKey: apiKey,
                configuration: configuration,
                autoStop: false,
                onSpeechStopped: {},
                onDelta: { _ in }
            )
            await realtimeClient.cancel(session: realtimeSession)
            _ = try await reasoningClient.testConnection(apiKey: apiKey, configuration: configuration)
            let latency = Date.now.timeIntervalSince(started)
            connectionState = .connected(milliseconds: Int(latency * 1_000))
        } catch {
            await realtimeClient.cancel(session: realtimeSession)
            connectionState = .failed(localizedError(error))
        }
    }

    func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { try keychain.remove(Keys.apiKey) }
        else { try keychain.set(trimmed, for: Keys.apiKey) }
        apiKey = trimmed
        connectionState = .idle
    }

    func playAudio(for entry: HistoryEntry) async throws -> Data {
        guard let filename = entry.audioFilename else { throw TextInteractionError.writeFailed }
        return try await store.audio(named: filename)
    }

    func retryDictation(_ id: UUID) async {
        guard let index = historyEntries.firstIndex(where: { $0.id == id }),
              historyEntries[index].mode == .dictation,
              historyEntries[index].status == .failed,
              let filename = historyEntries[index].audioFilename else { return }
        guard !apiKey.isEmpty else {
            showToast(text("请先保存 Qwen API Key", "Save your Qwen API Key first"), symbol: "key.fill")
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
                knowledgePrompt: KnowledgePrompt.render(
                    entities: knowledgeEntities,
                    relationships: knowledgeRelationships,
                    domains: selectedDomains,
                    customTerms: customDomainTerms,
                    purpose: .transcription
                )
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw QwenError.noSpeech }
            let cleaned = SpeechDisfluencyCleaner.clean(result, mode: dictationCleanup)
            updateHistory(id, input: cleaned, output: cleaned, status: .completed)
            showToast(text("识别成功，可从历史复制", "Transcribed; copy it from History"), symbol: "checkmark")
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
                ? text("已删除，星标记录都还在", "Deleted everything except starred items")
                : text("历史已清空", "History cleared"),
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
    func completeDomainOnboarding(domains: Set<DomainPreset>, customTerms: [String]) {
        let wasFirstRun = !didCompleteOnboarding
        selectedDomains = domains
        customDomainTerms = Self.normalizedDomainTerms(customTerms)
        didCompleteOnboarding = true
        presentedSheet = nil
        guard wasFirstRun else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.presentPermissionGuideIfNeeded()
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
            showToast(text("无法更新登录项，请在系统设置中检查", "Could not update Login Items; check System Settings"), symbol: "exclamationmark.triangle.fill")
        }
    }
    func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    func showToast(_ text: String, symbol: String) {
        let message = ToastMessage(text: text, symbol: symbol)
        toast = message
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
        NSApplication.shared.activate(ignoringOtherApps: true)
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
            showOverlayFeedback(text("请先添加 Qwen API Key", "Add your Qwen API Key first"), symbol: "key.fill", duration: .seconds(4))
            showMainWindow(destination: .settings)
            showToast(text("请先在 Qwen 连接中保存 API Key", "Save your API Key in Qwen connection first"), symbol: "key.fill")
            return
        }
        do {
            let snapshot = try textInteraction.captureTarget(requiringWindow: mode == .dictation)
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
                    customDomainTerms: customDomainTerms,
                    knowledge: knowledgeEntities,
                    isChineseUI: usesChineseUI
                )
                if let lastVerifiedWrite, lastVerifiedWrite.isRecent,
                   let expected = lastVerifiedWrite.expectedValue,
                   snapshot.valueBefore == expected,
                   textInteraction.currentValue(of: lastVerifiedWrite.target) == expected {
                    contextItems.append(ContextItem(
                        kind: .previousOutput,
                        symbol: "arrow.uturn.backward",
                        title: text("上次写入 · \(lastVerifiedWrite.text.count) 字", "Previous output · \(lastVerifiedWrite.text.count) chars"),
                        value: lastVerifiedWrite.text
                    ))
                }
                agentCommand = text("正在听…", "Listening…")
                dictationPhase = .idle
                agentPhase = .listening
            } else {
                agentPhase = .hidden
                dictationPhase = .idle
            }

            if mode == .dictation {
                let generation = workflowGeneration
                let (stream, continuation) = AsyncStream<Data>.makeStream()
                chunkContinuation = continuation
                try startAudioCapture { continuation.yield($0) }
                withAnimation(Motion.spring) { dictationPhase = .listening }
                let shouldAutoStop = autoStop
                let selectedRecognitionLanguage = recognitionLanguage
                let selectedNumberFormat = dictationNumberFormat
                let selectedCleanup = dictationCleanup
                let knowledgePrompt = KnowledgePrompt.render(
                    entities: knowledgeEntities,
                    relationships: knowledgeRelationships,
                    domains: selectedDomains,
                    customTerms: customDomainTerms,
                    purpose: .transcription
                )
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
                try startAudioCapture { _ in }
            }
            scheduleRecordingLimit(for: mode)
        } catch {
            handleWorkflowError(error, agent: mode == .agent)
        }
    }

    /// Warns shortly before the recording cap, then finishes the recording as if the user had stopped it.
    private func scheduleRecordingLimit(for mode: VoiceWorkflowMode) {
        let generation = workflowGeneration
        let limit = mode == .agent ? Self.agentRecordingLimit : Self.dictationRecordingLimit
        let warning = Self.recordingLimitWarning
        recordingLimitTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: limit - warning)
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
            if mode == .agent { self.finishAgentListening() } else { self.finishDictation() }
        }
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

    private func startAudioCapture(onChunk: @escaping @Sendable (Data) -> Void) throws {
        try audioCapture.start(
            onLevel: { [weak self] level in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.inputLevel = (self.inputLevel * 0.55) + (level * 0.45)
                }
            },
            onChunk: onChunk
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
                updateHistory(historyID, status: .completed)
                presentCopyFallback(raw, agent: false)
                await realtimeClient.cancel(session: realtimeSession)
                return
            }
            updateHistory(historyID, status: .completed)
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
        conversation: [AgentSession], generation: Int
    ) async {
        await persistHistoryAudio(recording, historyID: historyID)
        do {
            try Task.checkCancellation()
            guard generation == workflowGeneration else { throw CancellationError() }
            guard recording.hasSpeech else { throw QwenError.noSpeech }
            let includesKnowledge = context.contains { $0.kind == .knowledge }
            let includesDomains = context.contains { $0.kind == .domain }
            let knowledgePrompt = KnowledgePrompt.render(
                entities: includesKnowledge ? knowledgeEntities : [],
                relationships: includesKnowledge ? knowledgeRelationships : [],
                domains: includesDomains ? selectedDomains : [],
                customTerms: includesDomains ? customDomainTerms : [],
                purpose: .agent
            )
            let response = try await reasoningClient.respondToAudio(
                apiKey: apiKey,
                configuration: configuration,
                wav: recording.wav,
                context: context,
                sessions: context.contains(where: { $0.kind == .session }) ? conversation : [],
                knowledgePrompt: knowledgePrompt
            )
            try Task.checkCancellation()
            guard generation == workflowGeneration else { throw CancellationError() }
            guard let transcript = response.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !transcript.isEmpty else { throw QwenError.invalidResponse }
            let command = SpeechDisfluencyCleaner.clean(transcript, mode: .light)
            guard let snapshot else { throw TextInteractionError.targetChanged }
            updateHistory(historyID, input: command)
            agentCommand = response.intent
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

    private func transcribe(
        _ recording: AudioCapture.Recording, upload: Task<Void, Error>?,
        realtimeSession: UUID, generation: Int
    ) async throws -> String {
        guard recording.hasSpeech else {
            throw QwenError.noSpeech
        }
        do {
            try await upload?.value
            try Task.checkCancellation()
            guard generation == workflowGeneration else { throw CancellationError() }
            let result = try await realtimeClient.commit(session: realtimeSession)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw QwenError.noSpeech }
            return SpeechDisfluencyCleaner.clean(result, mode: dictationCleanup)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            guard generation == workflowGeneration else { throw CancellationError() }
            // Batch recognition only helps with transport problems; configuration errors would fail twice.
            guard QwenError.allowsBatchFallback(after: error) else { throw error }
            await realtimeClient.cancel(session: realtimeSession)
            let result = try await reasoningClient.transcribeAudio(
                apiKey: apiKey,
                configuration: configuration,
                wav: recording.wav,
                recognitionLanguage: recognitionLanguage,
                numberFormat: dictationNumberFormat,
                cleanup: dictationCleanup,
                knowledgePrompt: KnowledgePrompt.render(
                    entities: knowledgeEntities,
                    relationships: knowledgeRelationships,
                    domains: selectedDomains,
                    customTerms: customDomainTerms,
                    purpose: .transcription
                )
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw QwenError.noSpeech }
            return SpeechDisfluencyCleaner.clean(result, mode: dictationCleanup)
        }
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
            if response.action == .writeText {
                // Generated text is final prose, not a speech trace; cleaning it could alter names or code.
                guard let text = response.output, !text.isEmpty else { throw QwenError.invalidResponse }
                if automaticAgentWriteBack {
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
            } else {
                resultCanUndo = false
                try await AgentActionExecutor.execute(response)
                output = response.url ?? response.query ?? response.shortcutName ?? response.intent
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
            // Actions such as shortcuts can outlive a dismissed or newer workflow.
            guard generation == workflowGeneration else { return }
            if needsCopyFallback {
                presentCopyFallback(output, agent: true, copyImmediately: automaticAgentWriteBack)
                return
            }
            if response.action == .answer {
                pendingAnswerText = output
                pendingAnswerTarget = snapshot
                withAnimation(Motion.panel) { agentPhase = .answerReady }
                return
            }
            withAnimation(Motion.panel) { agentPhase = .result }
            try? await Task.sleep(for: Self.successDisplayDuration)
            if generation == workflowGeneration, agentPhase == .result {
                withAnimation(Motion.snappy) { agentPhase = .hidden }
            }
        } catch is CancellationError {
            updateHistory(historyID, status: .cancelled)
            if generation == workflowGeneration { agentPhase = .hidden }
        } catch {
            finishFailedWorkflow(error, historyID: historyID, agent: true, generation: generation)
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
        guard let snapshot = targetSnapshot, !snapshot.isSensitive else { return nil }
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
        if saveFailed {
            showToast(
                text("输入记录保存失败，识别仍会继续", "Could not save the input record; recognition will continue"),
                symbol: "exclamationmark.triangle.fill"
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
            showMainWindow(destination: .settings)
            showToast(message, symbol: "exclamationmark.triangle.fill")
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
                return text("为保护隐私，SayKuku 不会读写敏感输入框", "SayKuku does not read or write sensitive fields")
            case .targetChanged:
                return text("输入位置已改变，请重新触发", "The text target changed; trigger SayKuku again")
            case .writeFailed:
                return text("目标应用未接受文字，内容已复制", "The target app did not accept the text; it was copied")
            }
        }
        if let qwenError = error as? QwenError {
            switch qwenError {
            case .missingConfiguration:
                return text("请先填写 Qwen API Key", "Enter your Qwen API Key first")
            case .invalidEndpoint:
                return text("Qwen 连接设置有误，请检查地域和业务空间 ID", "Check your Qwen region and workspace ID")
            case .invalidResponse:
                return text("未获得可用结果，请重试", "No usable result was returned. Try again")
            case .noSpeech:
                return text("没有听清，请重试", "Didn't catch that. Try again")
            case .server(let status, _):
                if status == 401 || status == 403 {
                    return text("API Key 无效或没有权限，请检查 Qwen 设置", "Check your Qwen API Key and access")
                }
                if status == 429 {
                    return text("请求太频繁，请稍后重试", "Too many requests. Try again shortly")
                }
                if status == 400 {
                    return text("请求设置有误，请检查 Qwen 模型和业务空间 ID", "Check your Qwen model and workspace ID")
                }
                return text("Qwen 暂时无法处理请求，请重试", "Qwen could not process the request. Try again")
            case .protocolError:
                return text("Qwen 连接中断，请重试", "The Qwen connection was interrupted. Try again")
            case .timeout:
                return text("等待 Qwen 响应超时，请重试", "Qwen took too long to respond. Try again")
            case .recordingTooLong:
                return text("录音太长了，请分几段说", "That recording is too long. Try breaking it into shorter parts")
            }
        }
        if error is AudioCaptureError {
            return text("无法使用麦克风，请检查设备和权限", "Could not use the microphone. Check the device and permission")
        }
        if error is LocalStoreError {
            return text("无法读取本机记录，请重启 SayKuku 后重试", "Could not read local history. Restart SayKuku and try again")
        }
        if error is SecureStorageError {
            return text("无法保存 API Key，请检查这台 Mac 的钥匙串", "Could not save the API Key. Check this Mac's Keychain")
        }
        if error is URLError {
            return text("网络连接失败，请检查网络后重试", "Could not connect. Check your network and try again")
        }
        if error is AgentActionError {
            return text("快捷指令没有运行成功", "The shortcut didn't run successfully")
        }
        return text("操作失败，请重试", "Something went wrong. Try again")
    }

    private func loadStoredData() async {
        guard !isLoaded else { return }
        isLoaded = true
        localDataIssue = store.dataIssue
        if !defaults.bool(forKey: Keys.legacyDataNoticeDismissed) {
            legacyDataURL = await store.legacyEncryptedDataURL()
        }
        let snapshot: LocalStore.Snapshot
        do {
            snapshot = try await store.load()
        } catch {
            showToast(
                text("本地数据无法读取，新的更改暂不保存，详情见“历史”", "Couldn't read local data, so new changes won't be saved. See History for details"),
                symbol: "exclamationmark.triangle.fill"
            )
            return
        }
        historyEntries = Self.recoveringInterruptedHistory(
            snapshot.history,
            message: text("上次处理被中断", "Processing was interrupted")
        ).sorted { $0.createdAt > $1.createdAt }
        knowledgeEntities = snapshot.entities
        knowledgeRelationships = snapshot.relationships
        corrections = snapshot.corrections
        sessions = snapshot.sessions.filter { $0.expiresAt > .now }
        cleanExpiredHistory()
        if localDataIssue != nil {
            showToast(
                text("读取本地数据时出了问题，原文件已备份，详情见“历史”", "There was a problem reading local data. The original file was backed up; see History"),
                symbol: "exclamationmark.triangle.fill"
            )
        }
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

    private func schedulePersistence() {
        guard isLoaded else { return }
        persistenceGeneration += 1
        let generation = persistenceGeneration
        let value = LocalStore.Snapshot(
            history: historyEntries, entities: knowledgeEntities,
            relationships: knowledgeRelationships, corrections: corrections, sessions: sessions
        )
        Task { [store] in try? await store.replace(value, generation: generation) }
    }

    private func persistCurrentState() async throws {
        guard isLoaded else { return }
        persistenceGeneration += 1
        let generation = persistenceGeneration
        let value = LocalStore.Snapshot(
            history: historyEntries, entities: knowledgeEntities,
            relationships: knowledgeRelationships, corrections: corrections, sessions: sessions
        )
        try await store.replace(value, generation: generation)
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
        customDomainTerms = Self.normalizedDomainTerms(defaults.stringArray(forKey: Keys.customDomainTerms) ?? [])
        didCompleteOnboarding = defaults.bool(forKey: Keys.didCompleteOnboarding)
        if let raw = defaults.string(forKey: Keys.historyRetention), let value = HistoryRetention(rawValue: raw) { historyRetention = value }
        if let raw = defaults.string(forKey: Keys.qwenRegion), let value = QwenRegion(rawValue: raw) { qwenRegion = value }
        qwenWorkspaceID = defaults.string(forKey: Keys.qwenWorkspace) ?? ""
        let storedRealtimeModel = defaults.string(forKey: Keys.realtimeModel)
        if storedRealtimeModel == "qwen3.8-omni-flash-realtime"
            || storedRealtimeModel?.hasPrefix("qwen3-asr-flash-realtime") == true {
            realtimeModel = "qwen3.5-omni-flash-realtime"
        } else {
            realtimeModel = storedRealtimeModel ?? realtimeModel
        }
        reasoningModel = defaults.string(forKey: Keys.reasoningModel) ?? reasoningModel
        autoStop = defaults.object(forKey: Keys.autoStop).map { _ in defaults.bool(forKey: Keys.autoStop) } ?? false
        continuousConversation = defaults.object(forKey: Keys.continuousConversation).map { _ in defaults.bool(forKey: Keys.continuousConversation) } ?? true
        automaticAgentWriteBack = defaults.object(forKey: Keys.automaticAgentWriteBack).map { _ in defaults.bool(forKey: Keys.automaticAgentWriteBack) } ?? true
        learnFromCorrections = defaults.object(forKey: Keys.learnCorrections).map { _ in defaults.bool(forKey: Keys.learnCorrections) } ?? true
        selectedTextAllowed = defaults.object(forKey: Keys.selectedText).map { _ in defaults.bool(forKey: Keys.selectedText) } ?? true
        currentAppAllowed = defaults.object(forKey: Keys.currentApp).map { _ in defaults.bool(forKey: Keys.currentApp) } ?? true
        windowTitleAllowed = defaults.object(forKey: Keys.windowTitle).map { _ in defaults.bool(forKey: Keys.windowTitle) } ?? true
        clipboardAllowed = defaults.bool(forKey: Keys.clipboard)
        browserPageAllowed = defaults.bool(forKey: Keys.browserPage)
        storeVoiceAudio = defaults.object(forKey: Keys.storeVoiceAudio).map { _ in defaults.bool(forKey: Keys.storeVoiceAudio) } ?? true
        showInMenuBar = defaults.object(forKey: Keys.showInMenuBar).map { _ in defaults.bool(forKey: Keys.showInMenuBar) } ?? true
        hideDockIconAfterMainWindowCloses = defaults.object(forKey: Keys.hideDockIconAfterMainWindowCloses)
            .map { _ in defaults.bool(forKey: Keys.hideDockIconAfterMainWindowCloses) } ?? false
    }

    private enum Keys {
        static let inputMode = "inputMode", language = "appLanguage", autoStop = "autoStop"
        static let recognitionLanguage = "dictation.recognitionLanguage", dictationNumberFormat = "dictation.numberFormat"
        static let dictationCleanup = "dictation.cleanup"
        static let selectedDomains = "dictation.selectedDomains", customDomainTerms = "dictation.customDomainTerms"
        static let didCompleteOnboarding = "onboarding.completed"
        static let continuousConversation = "continuousConversation", learnCorrections = "learnFromCorrections"
        static let automaticAgentWriteBack = "agent.automaticWriteBack"
        static let selectedText = "privacy.selectedText", currentApp = "privacy.currentApp", windowTitle = "privacy.windowTitle"
        static let clipboard = "privacy.clipboard", browserPage = "privacy.browserPage"
        static let historyRetention = "historyRetention", storeVoiceAudio = "storeVoiceAudio", showInMenuBar = "showInMenuBar"
        static let hideDockIconAfterMainWindowCloses = "hideDockIconAfterMainWindowCloses"
        static let legacyDataNoticeDismissed = "history.legacyDataNoticeDismissed"
        static let qwenRegion = "qwen.region", qwenWorkspace = "qwen.workspace", realtimeModel = "qwen.realtimeModel"
        static let reasoningModel = "qwen.reasoningModel", apiKey = "qwen.apiKey"
    }

    private func presentStartupExperienceIfNeeded() {
        if didCompleteOnboarding { presentPermissionGuideIfNeeded() }
        else { presentedSheet = .onboarding }
    }

    nonisolated static func normalizedDomainTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.compactMap { term in
            let value = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 64 else { return nil }
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return value
        }.prefix(20).map { $0 }
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
        case .system: isChineseUI ? "跟随系统" : "Follow System"
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
