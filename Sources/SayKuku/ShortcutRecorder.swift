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
    func message(for action: GlobalShortcutAction) -> String {
        switch self {
        case .needsModifier:
            localized("Shortcuts need ⌘ or ⌃")
        case .unsupportedKey:
            localized("That key can’t be used. Try another.")
        case .reserved:
            localized("Shortcuts with only ⌘ or ⇧⌘ belong to apps. Add ⌃ or ⌥.")
        case .system:
            localized("macOS already uses this shortcut. Try another.")
        case .duplicate:
            localized("Already used for \(action.other.title). Try another.")
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

        let shape = RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)

        HStack(spacing: KukuSpacing.iconText) {
            Button {
                if isRecording { recorder.stop() } else { recorder.start(action, appState: appState) }
            } label: {
                Text(isRecording
                     ? localized("Press keys…")
                     : shortcut?.displayString ?? localized("Record Shortcut"))
                    .font(.kuku(.callout, weight: .semibold))
                    .foregroundStyle(isRecording ? KukuColor.accentText : shortcut == nil ? KukuColor.textSecondary : KukuColor.textPrimary)
                    .padding(.horizontal, KukuSpacing.md)
                    // Wide enough for "Record Shortcut" so the button doesn't resize while recording.
                    .frame(minWidth: 104, minHeight: KukuLayout.controlHeight)
                    .background(isRecording ? KukuColor.accentSubtle : KukuColor.fill, in: shape)
                    .overlay {
                        shape.strokeBorder(
                            isRecording ? KukuColor.focusRing : KukuColor.border,
                            lineWidth: isRecording ? KukuBorder.focusWidth : KukuBorder.width
                        )
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localized("Click, then press a new shortcut"))
            .accessibilityLabel(spokenLabel(isRecording: isRecording, shortcut: shortcut))

            if shortcut != nil, !isRecording {
                KukuIconButton(
                    symbol: "xmark.circle.fill",
                    label: localized("Turn off \(action.title) shortcut"),
                    size: .small,
                    tint: KukuColor.textTertiary
                ) {
                    appState.setGlobalShortcut(nil, for: action)
                }
            }
        }
    }

    private func spokenLabel(isRecording: Bool, shortcut: GlobalShortcut?) -> String {
        let title = action.title
        let value = if isRecording {
            localized("press new keys")
        } else if let shortcut {
            shortcut.spokenString
        } else {
            localized("off")
        }
        return localized("\(title) shortcut: \(value)")
    }
}
