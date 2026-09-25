import AppKit
import Observation
import os
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppState {
    enum Destination: String, CaseIterable, Identifiable {
        case home = "Home", history = "History", memory = "Memory"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .home: "house"
            case .history: "clock.arrow.circlepath"
            case .memory: "books.vertical"
            }
        }
        var title: String {
            switch self {
            case .home: localized("Home")
            case .history: localized("History")
            case .memory: localized("Memory")
            }
        }
    }

    enum ConnectionState: Equatable {
        case idle, testing, failed(String)
        /// `realtimeMilliseconds` is nil when realtime was skipped for lack of a workspace ID.
        case connected(realtimeMilliseconds: Int?, chatMilliseconds: Int)
    }

    var destination: Destination = .home
    var settingsSection: SettingsSection = .general
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
    let workflow: VoiceWorkflow
    let systemPermissions: SystemPermissionController
    let microphoneTest = MicrophoneTestController()
    /// Nil in dev builds and `swift run`, which never check for updates.
    let updateChecker: UpdateChecker?

    @ObservationIgnored private let reasoningClient: any Reasoning
    @ObservationIgnored private var shortcutController: ShortcutController?
    @ObservationIgnored private var mainWindowOpener: OpenWindowAction?
    @ObservationIgnored private var settingsOpener: OpenSettingsAction?
    @ObservationIgnored private var didEvaluateStartupPermissions = false
    @ObservationIgnored private var pendingSetupSteps: [AppSheet] = []
    @ObservationIgnored var savedForRelaunch = false

    static let mainWindowID = "main"

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
        let data = LocalData(store: store, settings: settings, persistenceDelay: persistenceDelay)
        self.data = data
        workflow = VoiceWorkflow(settings: settings, data: data, dependencies: dependencies)
        reasoningClient = dependencies.reasoningClient
        systemPermissions = dependencies.systemPermissions
        updateChecker = StorageIdentity() == .release ? UpdateChecker(bundle: .main, settings: settings) : nil
        launchAtLogin = SMAppService.mainApp.status == .enabled
        systemPermissions.accessibilityChangeHandler = { [weak self] in self?.refreshSystemPermissions() }
        settings.qwenConnectionChangeHandler = { [weak self] in self?.invalidateConnectionTest() }
        settings.historyRetentionChangeHandler = { [weak self] in self?.data.cleanExpiredHistory() }
        data.toastHandler = { [weak self] text, symbol in self?.showToast(text, symbol: symbol) }
        settings.globalShortcutChangeHandler = { [weak self] in self?.shortcutController?.reloadHotKeys() }
        workflow.toastHandler = { [weak self] text, symbol in self?.showToast(text, symbol: symbol) }
        workflow.settingsHandler = { [weak self] section in self?.showSettings(section: section) }
        workflow.permissionGuideHandler = { [weak self] in
            self?.showPermissionGuide()
            self?.showMainWindow()
        }
        updateChecker?.promptHandler = { feed, currentVersion in AppState.offerUpdate(feed, currentVersion: currentVersion) }
        if let currentVersion = updateChecker?.currentVersion {
            updateChecker?.resultHandler = { AppState.reportUpdateCheck($0, currentVersion: currentVersion) }
        }
    }

    func startSystemServices() {
        guard shortcutController == nil else { return }
        workflow.overlayController = FloatingOverlayController(appState: self)
        let controller = ShortcutController(appState: self)
        shortcutController = controller
        controller.start()
        updateChecker?.startPeriodicChecks()
        Task { await data.loadStoredData() }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.presentStartupExperienceIfNeeded()
        }
    }

    func analyzeMemory(_ source: String) async throws -> MemoryAnalysis {
        let redacted = MemoryPipeline.redactingPII(in: source)
        var entities: [ProposedEntity] = []
        for chunk in MemoryPipeline.chunks(redacted.text) {
            entities += try await reasoningClient.extractMemory(apiKey: settings.apiKey, configuration: settings.configuration, text: chunk)
        }
        return MemoryPipeline.analyze(proposals: entities, existing: data.memoryEntities, ignored: redacted.ignored)
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

    func copyText(_ text: String) {
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
        Task {
            guard await data.flushPersistence() else { return }
            // Release the global shortcuts first: the new instance registers them before this one quits.
            setGlobalShortcutsPaused(true)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { @Sendable _, error in
                Task { @MainActor in
                    guard let error else {
                        self.savedForRelaunch = true
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
    }
    /// Brings the app forward, then asks what to do about a new version; Download opens its page.
    private static func offerUpdate(_ feed: UpdateFeed, currentVersion: String) -> UpdateChecker.Response {
        let alert = NSAlert()
        alert.messageText = localized("SayKuku \(feed.version) is available")
        alert.informativeText = [localized("You’re using \(currentVersion)."), feed.shortNotes]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        alert.addButton(withTitle: localized("Download"))
        alert.addButton(withTitle: localized("Skip This Version"))
        alert.addButton(withTitle: localized("Later"))
        NSApplication.shared.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(feed.url)
            return .download
        case .alertSecondButtonReturn:
            return .skip
        default:
            return .later
        }
    }
    /// A manual check's answer, as an alert: Settings and the menu bar menu have no toast.
    private static func reportUpdateCheck(_ result: UpdateChecker.Decision, currentVersion: String) {
        let alert = NSAlert()
        if result == .upToDate {
            alert.messageText = localized("You’re up to date")
            alert.informativeText = localized("SayKuku \(currentVersion) is the latest version.")
        } else {
            alert.alertStyle = .warning
            alert.messageText = localized("Couldn’t check for updates")
            alert.informativeText = localized("Check your connection and try again.")
        }
        alert.addButton(withTitle: localized("OK"))
        NSApplication.shared.activate()
        _ = alert.runModal()
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
