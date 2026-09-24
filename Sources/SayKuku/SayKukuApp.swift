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
                .preferredColorScheme(.light)
                .background {
                    MainWindowReader { window in
                        appDelegate.observeMainWindow(window)
                    }
                }
                .modifier(MainWindowOpenerRegistration(appState: appState))
        }
        .defaultSize(width: 1_000, height: 660)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu(appState.text("语音", "Voice")) {
                Button(appState.text("开始语音输入    ⇧⌘D", "Start Voice Input    ⇧⌘D")) { appState.toggleDictation() }
                Button(appState.text("打开语音 Agent    ⇧⌘A", "Open Voice Agent    ⇧⌘A")) { appState.startAgent() }
            }
        }

        MenuBarExtra(isInserted: Binding(
            get: { appState.showInMenuBar },
            set: { setMenuBarVisibility($0) }
        )) {
            MenuBarContent()
                .environment(appState)
        } label: {
            // The status item appears at launch, so the opener is available even if the window never was.
            MenuBarIcon()
                .modifier(MainWindowOpenerRegistration(appState: appState))
        }
        .menuBarExtraStyle(.menu)
    }

    private func setMenuBarVisibility(_ isVisible: Bool) {
        if !isVisible, appState.hideDockIconAfterMainWindowCloses {
            appState.hideDockIconAfterMainWindowCloses = false
            NSApplication.shared.setActivationPolicy(.regular)
        }
        appState.setShowInMenuBar(isVisible)
    }
}

private struct MenuBarIcon: View {
    private static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "svg"),
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
        if appState.hideDockIconAfterMainWindowCloses {
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

        if appState.hideDockIconAfterMainWindowCloses {
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

/// Hands SwiftUI's window opener to AppState so shortcuts can reopen a closed main window.
private struct MainWindowOpenerRegistration: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let appState: AppState

    func body(content: Content) -> some View {
        content.onAppear { appState.registerMainWindowOpener(openWindow) }
    }
}

private struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(appState.text("开始语音输入", "Start Voice Input")) {
            appState.toggleDictation()
        }

        Button(appState.text("打开语音 Agent", "Open Voice Agent")) {
            appState.startAgent()
        }

        Divider()

        Button(appState.text("显示 SayKuku", "Show SayKuku")) {
            showWindow(destination: .home)
        }

        Button(appState.text("设置…", "Settings…")) {
            showWindow(destination: .settings)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Label(appState.shortcutStatus.title(appState), systemImage: appState.shortcutStatus.symbol)
            .disabled(true)

        Divider()

        Button(appState.text("退出 SayKuku", "Quit SayKuku")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func showWindow(destination: AppState.Destination) {
        appState.registerMainWindowOpener(openWindow)
        appState.showMainWindow(destination: destination)
    }
}
