import AppKit
import SwiftUI

enum AppSheet: String, Identifiable {
    case onboarding
    case permissions
    case qwenSetup

    var id: String { rawValue }
}

@main
struct SayKukuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Owned by the delegate so system services can start before any window exists.
    private var appState: AppState { appDelegate.appState }

    var body: some Scene {
        Window("SayKuku", id: AppState.mainWindowID) {
            RootView()
                .environment(appState)
                .frame(minWidth: 860, minHeight: 580)
                .background {
                    MainWindowReader { window in
                        appDelegate.observeMainWindow(window)
                    }
                }
                .modifier(WindowOpenerRegistration(appState: appState))
        }
        .defaultSize(width: 1_000, height: 660)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesItem(appState: appState)
            }
            CommandGroup(replacing: .newItem) { }
            FindCommands(appState: appState)
            CommandGroup(before: .sidebar) {
                PageMenuItems(appState: appState)
            }
            CommandMenu(localized("Voice")) {
                VoiceMenuItems(appState: appState)
            }
            CommandGroup(replacing: .help) {
                Button(localized("Email Feedback…")) {
                    composeFeedbackEmail()
                }
            }
        }

        // The system adds the ⌘, item to the app menu for this scene.
        Settings {
            SettingsView()
                .environment(appState)
                .frame(width: 720)
                .frame(minHeight: 480, idealHeight: 640)
                .background(KukuColor.canvas)
                .tint(KukuColor.coral)
        }
        .defaultSize(width: 720, height: 640)
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: Binding(
            get: { appState.settings.showInMenuBar },
            set: { setMenuBarVisibility($0) }
        )) {
            MenuBarContent()
                .environment(appState)
        } label: {
            // The status item appears at launch, so the openers are available even if the window never was.
            MenuBarIcon()
                .modifier(WindowOpenerRegistration(appState: appState))
        }
        .menuBarExtraStyle(.menu)
    }

    private func setMenuBarVisibility(_ isVisible: Bool) {
        if !isVisible, appState.settings.hideDockIconAfterMainWindowCloses {
            appState.settings.hideDockIconAfterMainWindowCloses = false
            NSApplication.shared.setActivationPolicy(.regular)
        }
        appState.settings.setShowInMenuBar(isVisible)
    }
}

extension Bundle {
    /// SwiftPM's `Bundle.module` only looks next to the `.app` and in the
    /// build-time `.build` path, and traps when neither exists. A packaged app
    /// keeps the resource bundle in `Contents/Resources`, so look there first.
    static let appResources: Bundle = Bundle.main
        .url(forResource: "SayKuku_SayKuku", withExtension: "bundle")
        .flatMap(Bundle.init(url:)) ?? .module
}

private struct MenuBarIcon: View {
    private static let image: NSImage? = {
        guard let url = Bundle.appResources.url(forResource: "MenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .renderingMode(.template)
            } else {
                Image(systemName: "circle.fill")
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel("SayKuku")
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var appState = AppState()
    private weak var mainWindow: NSWindow?
    private var suppressesLaunchWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.wasLaunchedAsLoginItem {
            suppressLaunchWindow()
        }
        appState.startSystemServices()
    }

    /// Covers every window, including Settings when the main window is closed.
    func applicationDidBecomeActive(_ notification: Notification) {
        appState.refreshSystemPermissions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Relaunch flushed the store before opening the new instance.
        if appState.savedForRelaunch { return .terminateNow }
        Task {
            let saved = await appState.data.flushPersistence()
            NSApplication.shared.reply(toApplicationShouldTerminate: saved || confirmQuitWithoutSaving())
        }
        return .terminateLater
    }

    private func confirmQuitWithoutSaving() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localized("Couldn’t save your latest changes")
        alert.addButton(withTitle: localized("Quit Anyway"))
        alert.addButton(withTitle: localized("Cancel"))
        return alert.runModalInFront() == .alertFirstButtonReturn
    }

    func observeMainWindow(_ window: NSWindow?) {
        guard let window, mainWindow !== window else { return }

        if let mainWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: mainWindow
            )
        }
        mainWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        if suppressesLaunchWindow { closeLaunchWindow(window) }
    }

    /// Login launches stay in the menu bar. SwiftUI may create the window before or after
    /// `applicationDidFinishLaunching`, so close it now or as soon as it appears.
    private func suppressLaunchWindow() {
        if appState.settings.hideDockIconAfterMainWindowCloses {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        if let mainWindow {
            closeLaunchWindow(mainWindow)
            return
        }
        suppressesLaunchWindow = true
        Task { @MainActor [weak self] in
            // Stop waiting so a window the user opens later is never closed.
            try? await Task.sleep(for: .seconds(2))
            self?.suppressesLaunchWindow = false
        }
    }

    private func closeLaunchWindow(_ window: NSWindow) {
        suppressesLaunchWindow = false
        Task { @MainActor in window.close() }
    }

    private static var wasLaunchedAsLoginItem: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    @objc private func mainWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, mainWindow === window else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: window
        )
        mainWindow = nil

        if appState.settings.hideDockIconAfterMainWindowCloses {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

private struct MainWindowReader: NSViewRepresentable {
    let onWindowChange: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowReaderView {
        WindowReaderView(onWindowChange: onWindowChange)
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) { }
}

private final class WindowReaderView: NSView {
    private let onWindowChange: @MainActor (NSWindow?) -> Void

    init(onWindowChange: @escaping @MainActor (NSWindow?) -> Void) {
        self.onWindowChange = onWindowChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange(window)
    }
}

/// Hands SwiftUI's window openers to AppState so shortcuts and alerts can open the main or Settings window.
private struct WindowOpenerRegistration: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    let appState: AppState

    func body(content: Content) -> some View {
        content.onAppear {
            appState.registerMainWindowOpener(openWindow)
            appState.registerSettingsOpener(openSettings)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VoiceMenuItems(appState: appState)

        Divider()

        Button(localized("Open SayKuku")) {
            showWindow(destination: .home)
        }

        Button(localized("Settings…")) {
            showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button(localized("Email Feedback…")) {
            composeFeedbackEmail()
        }

        Divider()

        shortcutStatusItem

        Divider()

        Button(localized("Quit SayKuku")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// A problem links to Settings › General, where it can be fixed; other states are informational.
    @ViewBuilder
    private var shortcutStatusItem: some View {
        let status = appState.shortcutStatus
        let label = Label(status.title(appState), systemImage: status.symbol)
        switch status {
        case .starting, .ready:
            label.disabled(true)
        case .accessibilityRequired, .hotKeyConflict:
            Button {
                showSettings(section: .general)
            } label: {
                label
            }
        }
    }

    private func showWindow(destination: AppState.Destination) {
        appState.registerMainWindowOpener(openWindow)
        appState.showMainWindow(destination: destination)
    }

    private func showSettings(section: SettingsSection? = nil) {
        appState.registerSettingsOpener(openSettings)
        appState.showSettings(section: section)
    }
}

@MainActor
private func composeFeedbackEmail() {
    guard let url = URL(string: "mailto:saykuku@ullrai.com?subject=SayKuku%20Feedback") else { return }
    NSWorkspace.shared.open(url)
}

/// Manual update check for the app menu; hidden in dev builds.
private struct CheckForUpdatesItem: View {
    let appState: AppState

    var body: some View {
        if let checker = appState.updateChecker {
            Button(localized("Check for Updates…")) {
                Task { await checker.checkManually() }
            }
            .disabled(checker.isChecking)
        }
    }
}

/// Find (⌘F) moves focus to the search field of the page in front; disabled on pages without one.
private struct FindCommands: Commands {
    let appState: AppState
    @FocusedValue(\.searchFieldFocus) private var searchFieldFocus: FocusState<Bool>.Binding?

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button(localized("Find…")) {
                if let searchFieldFocus { searchFieldFocus.wrappedValue = true }
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(searchFieldFocus == nil)
        }
    }
}

/// Page shortcuts for the View menu. Settings keeps its standard ⌘, item.
private struct PageMenuItems: View {
    let appState: AppState

    var body: some View {
        pageItem(.home, key: "1")
        pageItem(.history, key: "2")
        pageItem(.memory, key: "3")
        Divider()
    }

    private func pageItem(_ destination: AppState.Destination, key: KeyEquivalent) -> some View {
        Button(destination.title) {
            appState.showMainWindow(destination: destination)
        }
        .keyboardShortcut(key, modifiers: .command)
    }
}

/// Voice actions shared by the app menu and the menu bar menu.
///
/// The key equivalents only label the items with the registered global shortcuts.
/// A registered Carbon hot key consumes its keystroke before AppKit sees it, so
/// the menu item cannot fire a second time. While settings records a shortcut,
/// the hot keys are paused and the recorder's local monitor swallows the keys
/// before menu key equivalents are matched.
private struct VoiceMenuItems: View {
    let appState: AppState

    var body: some View {
        Button(appState.workflow.dictationPhase == .listening
               ? localized("Stop Voice Input")
               : localized("Start Voice Input")) {
            appState.workflow.toggleDictation()
        }
        .keyboardShortcut(keyboardShortcut(for: .voiceInput))

        Button(appState.workflow.agentPhase == .listening
               ? localized("Stop Voice Agent")
               : localized("Start Voice Agent")) {
            appState.workflow.startAgent()
        }
        .keyboardShortcut(keyboardShortcut(for: .voiceAgent))
    }

    /// Hides a shortcut that failed to register, since it would only work inside SayKuku.
    private func keyboardShortcut(for action: GlobalShortcutAction) -> KeyboardShortcut? {
        if case .hotKeyConflict(let failed) = appState.shortcutStatus, failed.contains(action) { return nil }
        return appState.settings.globalShortcut(for: action)?.keyboardShortcut
    }
}
