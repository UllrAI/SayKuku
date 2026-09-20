import AppKit
import ServiceManagement
import SwiftUI

enum AppSheet: String, Identifiable {
    case permissions

    var id: String { rawValue }
}

@main
struct SayKukuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        @Bindable var appState = appState

        Window("SayKuku.", id: "main") {
            RootView()
                .environment(appState)
                .frame(minWidth: 860, minHeight: 580)
                .preferredColorScheme(.light)
                .task { appState.startSystemServices() }
        }
        .defaultSize(width: 1_000, height: 660)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Voice") {
                Button("Start Voice Input    ⇧⌘D") { appState.toggleDictation() }
                Button("Open Voice Agent    ⇧⌘A") { appState.startAgent() }
            }
        }

        MenuBarExtra(isInserted: $appState.showInMenuBar) {
            MenuBarContent()
                .environment(appState)
        } label: {
            MenuBarMark()
        }
        .menuBarExtraStyle(.menu)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(appState.text("开始 Voice Input", "Start Voice Input")) {
            appState.toggleDictation()
        }

        Button(appState.text("打开 Voice Agent", "Open Voice Agent")) {
            appState.startAgent()
        }

        Divider()

        Button(appState.text("显示 SayKuku.", "Show SayKuku.")) {
            showWindow(destination: .home)
        }

        Button(appState.text("设置…", "Settings…")) {
            showWindow(destination: .settings)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Label(
            appState.shortcutStatus.title(appState),
            systemImage: appState.shortcutStatus.symbol
        )
        .disabled(true)

        Divider()

        Button(appState.text("退出 SayKuku.", "Quit SayKuku.")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func showWindow(destination: AppState.Destination) {
        appState.destination = destination
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
@Observable
final class AppState {
    enum Destination: String, CaseIterable, Identifiable {
        case home = "Home"
        case history = "History"
        case knowledge = "Knowledge"
        case memory = "Memory"
        case settings = "Settings"

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
    }

    enum DictationPhase: Equatable {
        case idle
        case ready
        case listening
        case processing
        case success
    }

    enum AgentPhase: Equatable {
        case hidden
        case listening
        case processing
        case result
    }

    enum ShortcutStatus: Equatable {
        case starting
        case ready
        case accessibilityRequired
        case hotKeyConflict

        var symbol: String {
            switch self {
            case .starting: "clock"
            case .ready: "checkmark.circle"
            case .accessibilityRequired: "exclamationmark.triangle"
            case .hotKeyConflict: "exclamationmark.triangle"
            }
        }

        @MainActor
        func title(_ appState: AppState) -> String {
            switch self {
            case .starting:
                appState.text("正在启动快捷键…", "Starting shortcuts…")
            case .ready:
                appState.text("Fn 与全局快捷键已就绪", "Fn and global shortcuts ready")
            case .accessibilityRequired:
                appState.text("全局快捷键可用 · Fn 需要辅助功能权限", "Global shortcuts ready · Fn needs Accessibility")
            case .hotKeyConflict:
                appState.text("快捷键被其他 App 占用，请检查冲突", "Shortcuts are in use by another app; check for conflicts")
            }
        }
    }

    var destination: Destination = .home
    var appLanguage: AppLanguage = .system
    var dictationPhase: DictationPhase = .idle {
        didSet { overlayController?.refresh() }
    }
    var agentPhase: AgentPhase = .hidden {
        didSet { overlayController?.refresh() }
    }
    var inputMode: InputMode = .hold {
        didSet { UserDefaults.standard.set(inputMode.rawValue, forKey: "inputMode") }
    }
    var autoStop = false
    var continuousConversation = true
    var learnFromCorrections = true
    var contextItems: [ContextItem] = ContextItem.samples
    var documentText = "我们计划下周完成这一版，然后进行内部测试。\n\n这个版本主要优化了性能，并修复了一些已知问题。\n\n我们也在同步准备下一个阶段的功能规划，预计会在下个月与大家分享更多细节。"
    var selectedRangeText = "我们计划下周完成这一版，然后进行内部测试。"
    var agentCommand = "翻译成英文，口语一点"
    var agentResult = "We’re planning to wrap this version up next week and start internal testing afterwards."
    var toast: ToastMessage?
    var importedEntityCount = 24
    var historyEntries = HistoryEntry.samples
    var historyRetention: HistoryRetention = .days30
    var storeVoiceAudio = true
    var shortcutStatus: ShortcutStatus = .starting
    var presentedSheet: AppSheet?
    var showInMenuBar = true {
        didSet { UserDefaults.standard.set(showInMenuBar, forKey: "showInMenuBar") }
    }
    var launchAtLogin = false
    let systemPermissions = SystemPermissionController()
    let microphoneTest = MicrophoneTestController()

    private var phaseTask: Task<Void, Never>?
    private var didEvaluateStartupPermissions = false
    @ObservationIgnored private var shortcutController: ShortcutController?
    @ObservationIgnored private var overlayController: FloatingOverlayController?

    init() {
        if let rawValue = UserDefaults.standard.string(forKey: "inputMode"),
           let savedMode = InputMode(rawValue: rawValue) {
            inputMode = savedMode
        }
        if UserDefaults.standard.object(forKey: "showInMenuBar") != nil {
            showInMenuBar = UserDefaults.standard.bool(forKey: "showInMenuBar")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var usesChineseUI: Bool {
        switch appLanguage {
        case .chinese:
            true
        case .english:
            false
        case .system:
            Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        }
    }

    func text(_ chinese: String, _ english: String) -> String {
        usesChineseUI ? chinese : english
    }

    func startDictation() {
        phaseTask?.cancel()
        agentPhase = .hidden
        dictationPhase = .ready
        phaseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.spring) { dictationPhase = .listening }
        }
    }

    func toggleDictation() {
        if dictationPhase == .ready || dictationPhase == .listening {
            finishDictation()
        } else {
            startDictation()
        }
    }

    func cancelDictation() {
        phaseTask?.cancel()
        withAnimation(Motion.snappy) { dictationPhase = .idle }
    }

    func finishDictation() {
        phaseTask?.cancel()
        withAnimation(Motion.snappy) { dictationPhase = .processing }
        phaseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.spring) { dictationPhase = .success }
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.snappy) { dictationPhase = .idle }
        }
    }

    func startAgent() {
        phaseTask?.cancel()
        dictationPhase = .idle
        agentPhase = .listening
    }

    func runAgent() {
        withAnimation(Motion.snappy) { agentPhase = .processing }
        phaseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_100))
            guard !Task.isCancelled else { return }
            if documentText.contains(selectedRangeText) {
                documentText = documentText.replacingOccurrences(of: selectedRangeText, with: agentResult)
                selectedRangeText = agentResult
            } else {
                documentText += agentResult
            }
            withAnimation(Motion.panel) { agentPhase = .result }
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.snappy) { agentPhase = .hidden }
        }
    }

    func dismissAgent() {
        phaseTask?.cancel()
        withAnimation(Motion.snappy) { agentPhase = .hidden }
    }

    func startSystemServices() {
        guard shortcutController == nil else { return }
        overlayController = FloatingOverlayController(appState: self)
        let controller = ShortcutController(appState: self)
        shortcutController = controller
        controller.start()
        presentPermissionGuideIfNeeded()
    }

    func presentPermissionGuideIfNeeded() {
        systemPermissions.refresh()
        guard !didEvaluateStartupPermissions else { return }
        didEvaluateStartupPermissions = true
        if !systemPermissions.allRequiredPermissionsGranted {
            presentedSheet = .permissions
        }
    }

    func showPermissionGuide() {
        systemPermissions.refresh()
        presentedSheet = .permissions
    }

    func dismissPermissionGuide() {
        microphoneTest.stop()
        presentedSheet = nil
    }

    func refreshSystemPermissions() {
        let accessibilityWasGranted = systemPermissions.accessibilityStatus.isAuthorized
        systemPermissions.refresh()
        if systemPermissions.accessibilityStatus.isAuthorized,
           !accessibilityWasGranted || shortcutStatus == .accessibilityRequired {
            shortcutController?.refreshAccessibilityPermission()
        }
    }

    @discardableResult
    func requestPermission(_ kind: SystemPermissionKind) async -> Bool {
        let granted = await systemPermissions.request(kind)
        refreshSystemPermissions()
        return granted
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            showToast(text("无法更新登录项，请在系统设置中检查", "Could not update Login Items; check System Settings"), symbol: "exclamationmark.triangle.fill")
        }
    }

    func openKeyboardSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func showToast(_ text: String, symbol: String) {
        toast = ToastMessage(text: text, symbol: symbol)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.7))
            withAnimation(Motion.snappy) { toast = nil }
        }
    }
}

enum InputMode: String, CaseIterable, Identifiable {
    case hold = "按住 Fn"
    case tap = "单击 Fn"

    var id: String { rawValue }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese
    case english

    var id: String { rawValue }

    func title(isChineseUI: Bool) -> String {
        switch self {
        case .system: isChineseUI ? "跟随系统" : "Follow System"
        case .chinese: "简体中文"
        case .english: "English"
        }
    }
}

struct ContextItem: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let title: String

    static let samples = [
        ContextItem(symbol: "safari", title: "Safari"),
        ContextItem(symbol: "text.quote", title: "Selected text · 28 字"),
        ContextItem(symbol: "folder", title: "Project · AniKuku")
    ]
}

struct ToastMessage: Equatable {
    let text: String
    let symbol: String
}
