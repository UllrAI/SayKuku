import AppKit
import SwiftUI

enum AppSheet: String, Identifiable {
    case onboarding
    case permissions

    var id: String { rawValue }
}

@main
struct SayKukuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        @Bindable var appState = appState

        Window("SayKuku", id: "main") {
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
                Button(appState.text("开始语音输入    ⇧⌘D", "Start Voice Input    ⇧⌘D")) { appState.toggleDictation() }
                Button(appState.text("打开语音 Agent    ⇧⌘A", "Open Voice Agent    ⇧⌘A")) { appState.startAgent() }
            }
        }

        MenuBarExtra("SayKuku", systemImage: "bird.fill", isInserted: $appState.showInMenuBar) {
            MenuBarContent()
                .environment(appState)
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
        appState.destination = destination
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
