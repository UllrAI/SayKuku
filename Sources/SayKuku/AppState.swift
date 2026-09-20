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
    enum AgentPhase: Equatable { case hidden, listening, transcribing, processing, result, copyReady }
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
    var continuousConversation = true { didSet { defaults.set(continuousConversation, forKey: Keys.continuousConversation) } }
    var learnFromCorrections = true { didSet { defaults.set(learnFromCorrections, forKey: Keys.learnCorrections) } }
    var selectedTextAllowed = true { didSet { defaults.set(selectedTextAllowed, forKey: Keys.selectedText) } }
    var currentAppAllowed = true { didSet { defaults.set(currentAppAllowed, forKey: Keys.currentApp) } }
    var windowTitleAllowed = true { didSet { defaults.set(windowTitleAllowed, forKey: Keys.windowTitle) } }
    var clipboardAllowed = false { didSet { defaults.set(clipboardAllowed, forKey: Keys.clipboard) } }
    var browserPageAllowed = false { didSet { defaults.set(browserPageAllowed, forKey: Keys.browserPage) } }
    var contextItems: [ContextItem] = []
    var agentCommand = ""
    var liveTranscript = ""
    var pendingCopyText = ""
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
    var shortcutStatus: ShortcutStatus = .starting
    var presentedSheet: AppSheet?
    var showInMenuBar = true { didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) } }
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
    @ObservationIgnored private let keychain = KeychainStore()
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
    @ObservationIgnored private var activeAgentTranscript = ""
    @ObservationIgnored private var activeAgentSession: AgentSession?
    @ObservationIgnored private var activeRecording: AudioCapture.Recording?
    @ObservationIgnored private var didEvaluateStartupPermissions = false
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var persistenceGeneration = 0

    init(defaults: UserDefaults = .standard, store: LocalStore = LocalStore()) {
        self.defaults = defaults
        self.store = store
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

    var currentSession: AgentSession? {
        let now = Date.now
        return sessions.filter { $0.expiresAt > now }.max(by: { $0.createdAt < $1.createdAt })
    }

    func text(_ chinese: String, _ english: String) -> String { usesChineseUI ? chinese : english }

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
        let recording = audioCapture.stop()
        activeRecording = recording
        chunkContinuation?.finish()
        chunkContinuation = nil
        withAnimation(Motion.snappy) { dictationPhase = .processing }
        workflowTask = Task { [weak self] in await self?.completeDictation(recording) }
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
        let recording = audioCapture.stop()
        activeRecording = recording
        chunkContinuation?.finish()
        chunkContinuation = nil
        withAnimation(Motion.snappy) { agentPhase = .transcribing }
        workflowTask = Task { [weak self] in await self?.processAgentRecording(recording) }
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
            self?.presentPermissionGuideIfNeeded()
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
        let resolvedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidate = KnowledgeEntity(
            name: trimmed,
            detail: resolvedDetail.isEmpty ? text("手动添加", "Added manually") : resolvedDetail,
            type: type,
            aliases: aliases
        )
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
        let entity = KnowledgeEntity(name: record.corrected, detail: text("来自纠正记忆", "From correction memory"), type: .term, aliases: [record.raw], source: .correction)
        if let entityIndex = knowledgeEntities.firstIndex(where: { $0.normalizedKey == entity.normalizedKey }) {
            if !knowledgeEntities[entityIndex].aliases.contains(record.raw) { knowledgeEntities[entityIndex].aliases.append(record.raw) }
        } else {
            knowledgeEntities.append(entity)
        }
    }

    func ignoreCorrection(_ id: UUID) {
        if let index = corrections.firstIndex(where: { $0.id == id }) { corrections[index].status = .ignored }
    }

    func testQwenConnection() async {
        connectionState = .testing
        do {
            try saveAPIKey(apiKey)
            let started = Date.now
            try await realtimeClient.connect(
                apiKey: apiKey,
                configuration: configuration,
                autoStop: false,
                onSpeechStopped: {},
                onDelta: { _ in }
            )
            await realtimeClient.cancel()
            _ = try await reasoningClient.testConnection(apiKey: apiKey, configuration: configuration)
            let latency = Date.now.timeIntervalSince(started)
            connectionState = .connected(milliseconds: Int(latency * 1_000))
        } catch {
            await realtimeClient.cancel()
            connectionState = .failed(error.localizedDescription)
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

    func presentPermissionGuideIfNeeded() {
        systemPermissions.refresh()
        guard !didEvaluateStartupPermissions else { return }
        didEvaluateStartupPermissions = true
        if !systemPermissions.allRequiredPermissionsGranted { presentedSheet = .permissions }
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
        toast = ToastMessage(text: text, symbol: symbol)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(Motion.snappy) { self?.toast = nil }
        }
    }

    private enum VoiceWorkflowMode: Sendable { case dictation, agent }

    private func beginVoiceWorkflow(mode: VoiceWorkflowMode) {
        cancelWorkflow()
        guard systemPermissions.microphoneStatus == .authorized else {
            showPermissionGuide()
            return
        }
        guard !apiKey.isEmpty else {
            destination = .settings
            showToast(text("请先在 Qwen & API 中保存 API Key", "Save your API Key in Qwen & API first"), symbol: "key.fill")
            return
        }
        do {
            let snapshot = try textInteraction.captureTarget()
            guard !snapshot.isSensitive else { throw TextInteractionError.sensitiveTarget }
            targetSnapshot = snapshot
            liveTranscript = ""
            pendingCopyText = ""
            activeAgentTranscript = ""
            activeAgentSession = nil
            activeRecording = nil
            if mode == .agent {
                let session = continuousConversation
                    ? sessions.filter { $0.app == snapshot.bundleID && $0.expiresAt > .now }.max(by: { $0.createdAt < $1.createdAt })
                    : nil
                activeAgentSession = session
                contextItems = ContextCollector.collect(
                    snapshot: snapshot,
                    selectedTextAllowed: selectedTextAllowed,
                    currentAppAllowed: currentAppAllowed,
                    windowTitleAllowed: windowTitleAllowed,
                    clipboardAllowed: clipboardAllowed,
                    browserPageAllowed: browserPageAllowed,
                    session: session,
                    knowledge: knowledgeEntities
                )
                agentCommand = text("正在听…", "Listening…")
                dictationPhase = .idle
                agentPhase = .listening
            } else {
                agentPhase = .hidden
                dictationPhase = .idle
            }

            if mode == .dictation {
                let (stream, continuation) = AsyncStream<Data>.makeStream()
                chunkContinuation = continuation
                try audioCapture.start { continuation.yield($0) }
                withAnimation(Motion.spring) { dictationPhase = .listening }
                let shouldAutoStop = autoStop
                uploadTask = Task { [weak self, realtimeClient, apiKey, configuration] in
                    try await realtimeClient.connect(
                        apiKey: apiKey,
                        configuration: configuration,
                        autoStop: shouldAutoStop,
                        onSpeechStopped: {
                            Task { @MainActor in self?.finishDictation() }
                        },
                        onDelta: { transcript in Task { @MainActor in self?.liveTranscript = transcript } }
                    )
                    for await chunk in stream { await realtimeClient.append(chunk) }
                }
            } else {
                try audioCapture.start { _ in }
            }
        } catch {
            handleWorkflowError(error, agent: mode == .agent)
        }
    }

    private func completeDictation(_ recording: AudioCapture.Recording) async {
        do {
            let raw = try await transcribe(recording)
            guard !raw.isEmpty else { throw QwenError.invalidResponse }
            let final = KnowledgePipeline.corrected(raw, using: knowledgeEntities)
            guard let snapshot = targetSnapshot else { throw TextInteractionError.targetChanged }
            do {
                try await textInteraction.write(final, to: snapshot)
                observeCorrection(writtenText: final, snapshot: snapshot)
            } catch is TextInteractionError {
                await recordHistory(mode: .dictation, input: raw, output: final, recording: recording, snapshot: snapshot)
                presentCopyFallback(final, agent: false)
                await realtimeClient.cancel()
                return
            }
            await recordHistory(mode: .dictation, input: raw, output: final, recording: recording, snapshot: snapshot)
            withAnimation(Motion.spring) { dictationPhase = .success }
            try? await Task.sleep(for: .milliseconds(850))
            withAnimation(Motion.snappy) { dictationPhase = .idle }
        } catch is CancellationError {
            dictationPhase = .idle
        } catch {
            handleWorkflowError(error, agent: false)
        }
        await realtimeClient.cancel()
    }

    private func processAgentRecording(_ recording: AudioCapture.Recording) async {
        do {
            guard recording.hasSpeech else { throw QwenError.noSpeech }
            let response = try await reasoningClient.respondToAudio(
                apiKey: apiKey,
                configuration: configuration,
                wav: recording.wav,
                context: contextItems,
                session: activeAgentSession
            )
            guard let command = response.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !command.isEmpty else { throw QwenError.invalidResponse }
            guard let snapshot = targetSnapshot else { throw TextInteractionError.targetChanged }
            activeAgentTranscript = command
            agentCommand = response.intent
            withAnimation(Motion.panel) { agentPhase = .processing }
            await executeAgent(response, snapshot: snapshot)
        } catch is CancellationError {
            agentPhase = .hidden
        } catch {
            handleWorkflowError(error, agent: true)
        }
        await realtimeClient.cancel()
    }

    private func transcribe(_ recording: AudioCapture.Recording) async throws -> String {
        guard recording.hasSpeech else {
            throw QwenError.noSpeech
        }
        do {
            try await uploadTask?.value
            let result = try await realtimeClient.commit().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw QwenError.noSpeech }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch QwenError.noSpeech {
            throw QwenError.noSpeech
        } catch {
            await realtimeClient.cancel()
            let result = try await reasoningClient.transcribeAudio(apiKey: apiKey, configuration: configuration, wav: recording.wav)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw QwenError.noSpeech }
            return result
        }
    }

    private func executeAgent(_ response: AgentResponse, snapshot: TextTargetSnapshot) async {
        do {
            let output: String
            var needsCopyFallback = false
            if response.action == .writeText {
                guard let text = response.output, !text.isEmpty else { throw QwenError.invalidResponse }
                do {
                    try await textInteraction.write(text, to: snapshot)
                } catch is TextInteractionError {
                    needsCopyFallback = true
                }
                output = text
            } else {
                try AgentActionExecutor.execute(response)
                output = response.url ?? response.query ?? response.shortcutName ?? response.intent
            }
            if let recording = activeRecording {
                await recordHistory(mode: .agent, input: activeAgentTranscript, output: output, recording: recording, snapshot: snapshot)
            }
            if continuousConversation {
                sessions.removeAll { $0.expiresAt <= .now || $0.app == snapshot.bundleID }
                sessions.append(AgentSession(
                    app: snapshot.bundleID,
                    contextSummary: contextItems.map(\.title).joined(separator: " · "),
                    userCommand: activeAgentTranscript,
                    response: output,
                    expiresAt: .now.addingTimeInterval(30 * 60)
                ))
            }
            if needsCopyFallback {
                presentCopyFallback(output, agent: true)
                return
            }
            withAnimation(Motion.panel) { agentPhase = .result }
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(Motion.snappy) { agentPhase = .hidden }
        } catch is CancellationError {
            agentPhase = .hidden
        } catch {
            handleWorkflowError(error, agent: true)
        }
    }

    private func recordHistory(
        mode: HistoryMode, input: String, output: String,
        recording: AudioCapture.Recording, snapshot: TextTargetSnapshot
    ) async {
        guard !snapshot.isSensitive else { return }
        let id = UUID()
        var filename: String?
        if storeVoiceAudio, !recording.wav.isEmpty { filename = try? await store.saveAudio(recording.wav, id: id) }
        historyEntries.insert(HistoryEntry(
            id: id, mode: mode, app: snapshot.appName, durationSeconds: recording.duration,
            input: input, output: output, audioFilename: filename
        ), at: 0)
        cleanExpiredHistory()
    }

    private func cancelWorkflow() {
        workflowTask?.cancel()
        workflowTask = nil
        uploadTask?.cancel()
        uploadTask = nil
        chunkContinuation?.finish()
        chunkContinuation = nil
        audioCapture.cancel()
        Task { await realtimeClient.cancel() }
        targetSnapshot = nil
        activeAgentTranscript = ""
        activeAgentSession = nil
        activeRecording = nil
        pendingCopyText = ""
    }

    private func presentCopyFallback(_ text: String, agent: Bool) {
        pendingCopyText = text
        copyPendingText()
        withAnimation(Motion.panel) {
            if agent { agentPhase = .copyReady }
            else { dictationPhase = .copyReady }
        }
    }

    private func handleWorkflowError(_ error: Error, agent: Bool) {
        audioCapture.cancel()
        chunkContinuation?.finish()
        chunkContinuation = nil
        uploadTask?.cancel()
        if agent { agentPhase = .hidden } else { dictationPhase = .idle }
        showToast(localizedError(error), symbol: "exclamationmark.triangle.fill")
    }

    private func observeCorrection(writtenText: String, snapshot: TextTargetSnapshot) {
        guard learnFromCorrections, let before = snapshot.valueBefore, let range = snapshot.selectedRange else { return }
        let source = before as NSString
        guard range.location >= 0, range.length >= 0, NSMaxRange(NSRange(location: range.location, length: range.length)) <= source.length else { return }
        let expected = source.replacingCharacters(in: NSRange(location: range.location, length: range.length), with: writtenText)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, let actual = self.textInteraction.currentValue(of: snapshot), actual != expected,
                  let change = Self.changedSegments(expected: expected, actual: actual),
                  !change.before.isEmpty, !change.after.isEmpty,
                  change.before.count <= 100, change.after.count <= 100,
                  change.range.lowerBound <= range.location + (writtenText as NSString).length,
                  change.range.upperBound >= range.location else { return }
            if let index = self.corrections.firstIndex(where: { $0.raw == change.before && $0.corrected == change.after }) {
                self.corrections[index].count += 1
                self.corrections[index].lastSeenAt = .now
                self.corrections[index].lastApp = snapshot.appName
            } else {
                self.corrections.append(CorrectionRecord(raw: change.before, corrected: change.after, lastApp: snapshot.appName))
            }
        }
    }

    private static func changedSegments(expected: String, actual: String) -> (before: String, after: String, range: Range<Int>)? {
        let left = Array(expected.utf16), right = Array(actual.utf16)
        var prefix = 0
        while prefix < min(left.count, right.count), left[prefix] == right[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(left.count - prefix, right.count - prefix),
              left[left.count - 1 - suffix] == right[right.count - 1 - suffix] { suffix += 1 }
        guard prefix < left.count || prefix < right.count else { return nil }
        let oldUnits = Array(left[prefix..<(left.count - suffix)])
        let newUnits = Array(right[prefix..<(right.count - suffix)])
        return (
            String(decoding: oldUnits, as: UTF16.self),
            String(decoding: newUnits, as: UTF16.self),
            prefix..<(left.count - suffix)
        )
    }

    private func localizedError(_ error: Error) -> String {
        if let qwenError = error as? QwenError, qwenError == .noSpeech {
            return text("未检测到语音，请靠近麦克风后重试", "No speech detected; move closer to the microphone and try again")
        }
        if error is TextInteractionError {
            return text("请先点一下要输入文字的位置，再试一次", "Click where you want to type, then try again")
        }
        let message = error.localizedDescription
        if usesChineseUI {
            if error is QwenError { return "Qwen 请求失败：\(message)" }
        }
        return message
    }

    private func loadStoredData() async {
        guard !isLoaded else { return }
        isLoaded = true
        let snapshot = await store.load()
        historyEntries = snapshot.history.sorted { $0.createdAt > $1.createdAt }
        knowledgeEntities = snapshot.entities
        knowledgeRelationships = snapshot.relationships
        corrections = snapshot.corrections
        sessions = snapshot.sessions.filter { $0.expiresAt > .now }
        cleanExpiredHistory()
    }

    private func cleanExpiredHistory() {
        guard let days = historyRetention.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return }
        let removed = historyEntries.filter { !$0.isStarred && $0.createdAt < cutoff }
        guard !removed.isEmpty else { return }
        historyEntries.removeAll { !$0.isStarred && $0.createdAt < cutoff }
        Task { [store] in
            for entry in removed { if let filename = entry.audioFilename { try? await store.removeAudio(named: filename) } }
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

    private func loadSettings() {
        if let raw = defaults.string(forKey: Keys.inputMode), let value = InputMode(rawValue: raw) { inputMode = value }
        if let raw = defaults.string(forKey: Keys.language), let value = AppLanguage(rawValue: raw) { appLanguage = value }
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
        learnFromCorrections = defaults.object(forKey: Keys.learnCorrections).map { _ in defaults.bool(forKey: Keys.learnCorrections) } ?? true
        selectedTextAllowed = defaults.object(forKey: Keys.selectedText).map { _ in defaults.bool(forKey: Keys.selectedText) } ?? true
        currentAppAllowed = defaults.object(forKey: Keys.currentApp).map { _ in defaults.bool(forKey: Keys.currentApp) } ?? true
        windowTitleAllowed = defaults.object(forKey: Keys.windowTitle).map { _ in defaults.bool(forKey: Keys.windowTitle) } ?? true
        clipboardAllowed = defaults.bool(forKey: Keys.clipboard)
        browserPageAllowed = defaults.bool(forKey: Keys.browserPage)
        storeVoiceAudio = defaults.object(forKey: Keys.storeVoiceAudio).map { _ in defaults.bool(forKey: Keys.storeVoiceAudio) } ?? true
        showInMenuBar = defaults.object(forKey: Keys.showInMenuBar).map { _ in defaults.bool(forKey: Keys.showInMenuBar) } ?? true
    }

    private enum Keys {
        static let inputMode = "inputMode", language = "appLanguage", autoStop = "autoStop"
        static let continuousConversation = "continuousConversation", learnCorrections = "learnFromCorrections"
        static let selectedText = "privacy.selectedText", currentApp = "privacy.currentApp", windowTitle = "privacy.windowTitle"
        static let clipboard = "privacy.clipboard", browserPage = "privacy.browserPage"
        static let historyRetention = "historyRetention", storeVoiceAudio = "storeVoiceAudio", showInMenuBar = "showInMenuBar"
        static let qwenRegion = "qwen.region", qwenWorkspace = "qwen.workspace", realtimeModel = "qwen.realtimeModel"
        static let reasoningModel = "qwen.reasoningModel", apiKey = "qwen.apiKey"
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

struct ToastMessage: Equatable { let text: String; let symbol: String }
