import AppKit
import SwiftUI

/// Captures the next key combination for a global shortcut. Global hot keys are
/// paused while recording so the current combination reaches the recorder.
@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var action: GlobalShortcutAction?
    private(set) var issue: GlobalShortcut.RecordingIssue?

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?

    func start(_ action: GlobalShortcutAction, appState: AppState) {
        stop()
        self.appState = appState
        self.action = action
        appState.setGlobalShortcutsPaused(true)

        // Local monitors run before menu key equivalents, so returning nil keeps
        // the recorded keys from also triggering a menu item.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let modifiers = GlobalShortcut.carbonModifiers(from: event.modifierFlags)
            let consumed = MainActor.assumeIsolated {
                self?.receive(keyCode: keyCode, modifiers: modifiers) ?? false
            }
            return consumed ? nil : event
        }
        // Keys typed in other apps never reach a local monitor; stop instead of
        // leaving the global shortcuts paused.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.stop() }
        }
    }

    func stop() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        guard action != nil else { return }
        action = nil
        issue = nil
        appState?.setGlobalShortcutsPaused(false)
    }

    private func receive(keyCode: UInt16, modifiers: UInt32) -> Bool {
        guard let action, let appState else { return false }
        let result = GlobalShortcut.recordingResult(
            keyCode: keyCode,
            carbonModifiers: modifiers,
            otherShortcut: appState.globalShortcut(for: action.other)
        )
        switch result {
        case .cancel:
            stop()
        case .clear:
            appState.setGlobalShortcut(nil, for: action)
            stop()
        case .record(let shortcut):
            appState.setGlobalShortcut(shortcut, for: action)
            stop()
        case .reject(let issue):
            self.issue = issue
        }
        return true
    }
}

extension GlobalShortcut.RecordingIssue {
    @MainActor func message(for action: GlobalShortcutAction, _ appState: AppState) -> String {
        switch self {
        case .needsModifier:
            appState.text("需包含 ⌘ 或 ⌃", "Include ⌘ or ⌃")
        case .unsupportedKey:
            appState.text("这个键不能用作快捷键，请换一个", "That key can’t be used. Try another.")
        case .duplicate:
            appState.text(
                "已用于\(action.other.title(appState))，请换一个",
                "Already used for \(action.other.title(appState)). Try another."
            )
        }
    }
}

/// Shows the active combination; click to record a new one.
struct ShortcutRecorderButton: View {
    @Environment(AppState.self) private var appState
    let action: GlobalShortcutAction
    let recorder: ShortcutRecorder

    var body: some View {
        let isRecording = recorder.action == action
        let shortcut = appState.globalShortcut(for: action)

        HStack(spacing: 6) {
            Button {
                if isRecording { recorder.stop() } else { recorder.start(action, appState: appState) }
            } label: {
                Text(isRecording
                     ? appState.text("按下快捷键…", "Press keys…")
                     : shortcut?.displayString ?? appState.text("录制快捷键", "Record Shortcut"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isRecording ? KukuColor.coral : shortcut == nil ? KukuColor.stone : KukuColor.ink)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 104, minHeight: 28)
                    .background(
                        isRecording ? KukuColor.coral.opacity(0.075) : KukuColor.shade.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                            .stroke(isRecording ? KukuColor.coral.opacity(0.4) : KukuColor.line, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(appState.text("点击后按下新的组合键", "Click, then press a new shortcut"))

            if shortcut != nil, !isRecording {
                Button {
                    appState.setGlobalShortcut(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(KukuColor.stone)
                }
                .buttonStyle(.plain)
                .help(appState.text("关闭这个快捷键", "Turn off this shortcut"))
                .accessibilityLabel(appState.text("关闭快捷键", "Turn off shortcut"))
            }
        }
    }
}
