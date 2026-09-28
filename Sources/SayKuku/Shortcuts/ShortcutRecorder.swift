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
    @ObservationIgnored private var modifierCandidate: UInt16?

    func start(_ action: GlobalShortcutAction, appState: AppState) {
        stop()
        self.appState = appState
        self.action = action
        appState.setGlobalShortcutsPaused(true)

        // Local monitors run before menu key equivalents, so returning nil keeps
        // the recorded keys from also triggering a menu item.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                self?.receive(event) ?? false
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
        modifierCandidate = nil
        appState?.setGlobalShortcutsPaused(false)
    }

    private func receive(_ event: NSEvent) -> Bool {
        guard let action, let appState else { return false }
        let otherShortcut = appState.settings.globalShortcut(for: action.other)
        if event.type == .flagsChanged {
            guard let flag = GlobalShortcut.modifierFlag(for: event.keyCode) else { return false }
            let released = modifierCandidate == event.keyCode && !event.modifierFlags.contains(flag)
            if released {
                modifierCandidate = nil
                if let result = GlobalShortcut.modifierOnlyResult(keyCode: event.keyCode, otherShortcut: otherShortcut) {
                    apply(result, action: action, appState: appState)
                }
            } else {
                modifierCandidate = GlobalShortcut.carbonModifiers(from: event.modifierFlags)
                    == GlobalShortcut.carbonModifiers(from: flag) ? event.keyCode : nil
            }
            return true
        }
        modifierCandidate = nil
        let result = GlobalShortcut.recordingResult(
            keyCode: event.keyCode,
            carbonModifiers: GlobalShortcut.carbonModifiers(from: event.modifierFlags),
            otherShortcut: otherShortcut
        )
        apply(result, action: action, appState: appState)
        return true
    }

    private func apply(_ result: GlobalShortcut.RecordingResult, action: GlobalShortcutAction, appState: AppState) {
        switch result {
        case .cancel:
            stop()
        case .clear:
            appState.settings.setGlobalShortcut(nil, for: action)
            stop()
        case .record(let shortcut):
            appState.settings.setGlobalShortcut(shortcut, for: action)
            stop()
        case .reject(let issue):
            self.issue = issue
        }
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
    @State private var showingChoices = false
    let action: GlobalShortcutAction
    let recorder: ShortcutRecorder

    var body: some View {
        let isRecording = recorder.action == action
        let shortcut = appState.settings.globalShortcut(for: action)
        let suggestedDoubleTap = suggestedDoubleTap

        let shape = RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)

        ZStack(alignment: .trailing) {
            Button {
                if isRecording {
                    recorder.stop()
                } else if suggestedDoubleTap != nil, recorder.action == nil {
                    showingChoices = true
                } else {
                    recorder.start(action, appState: appState)
                }
            } label: {
                controlLabel(isRecording: isRecording, shortcut: shortcut, shape: shape)
            }
            .buttonStyle(.plain)
            .help(suggestedDoubleTap == nil
                ? localized("Click, then press a new shortcut")
                : localized("Choose a double tap or record another shortcut"))
            .accessibilityLabel(spokenLabel(isRecording: isRecording, shortcut: shortcut))
            .popover(isPresented: $showingChoices, arrowEdge: .bottom) {
                if let suggestedDoubleTap {
                    VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                        Button(localized("Double-press \(GlobalShortcut(keyCode: suggestedDoubleTap.keyCode, carbonModifiers: 0).displayString)")) {
                            appState.settings.setGlobalShortcut(suggestedDoubleTap, for: action)
                            showingChoices = false
                        }
                        .buttonStyle(.kukuSecondary)

                        Button(localized("Record another shortcut…")) {
                            showingChoices = false
                            recorder.start(action, appState: appState)
                        }
                        .buttonStyle(.kukuSecondary)
                    }
                    .frame(minWidth: 210)
                    .padding(KukuSpacing.md)
                }
            }

            if shortcut != nil, !isRecording {
                KukuIconButton(
                    symbol: "xmark.circle.fill",
                    label: localized("Turn off \(action.title) shortcut"),
                    size: .small,
                    tint: KukuColor.textTertiary
                ) {
                    appState.settings.setGlobalShortcut(nil, for: action)
                }
                .padding(.trailing, KukuSpacing.xxs)
            }
        }
    }

    private var suggestedDoubleTap: GlobalShortcut? {
        guard action == .voiceAgent,
              let inputShortcut = appState.settings.voiceInputShortcut,
              inputShortcut.isModifierOnly,
              inputShortcut.modifierTapCount == 1 else { return nil }
        return GlobalShortcut(keyCode: inputShortcut.keyCode, carbonModifiers: 0, modifierTapCount: 2)
    }

    private func controlLabel(
        isRecording: Bool,
        shortcut: GlobalShortcut?,
        shape: RoundedRectangle
    ) -> some View {
        Text(isRecording ? localized("Press keys…") : shortcut?.displayString ?? localized("Record Shortcut"))
            .font(.kuku(.callout, weight: .semibold))
            .foregroundStyle(isRecording ? KukuColor.accentText : shortcut == nil ? KukuColor.textSecondary : KukuColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, KukuSpacing.md)
            .frame(width: 148, height: KukuLayout.controlHeight)
            .background(isRecording ? KukuColor.accentSubtle : KukuColor.fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    isRecording ? KukuColor.focusRing : KukuColor.border,
                    lineWidth: isRecording ? KukuBorder.focusWidth : KukuBorder.width
                )
            }
            .contentShape(Rectangle())
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
