import ApplicationServices
import AppKit
import Carbon.HIToolbox
import os

struct KeyboardEventSample: Sendable {
    enum Kind: Sendable {
        case flagsChanged
        case keyDown
        case otherInput
    }

    let kind: Kind
    let functionIsPressed: Bool
    let keyCode: UInt16
    let timestamp: TimeInterval
    var carbonModifiers: UInt32 = 0

    static func from(_ event: NSEvent) -> Self? {
        let kind: Kind
        switch event.type {
        case .flagsChanged:
            kind = .flagsChanged
        case .keyDown:
            kind = .keyDown
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel:
            kind = .otherInput
        default:
            return nil
        }

        return Self(
            kind: kind,
            functionIsPressed: event.modifierFlags.contains(.function),
            keyCode: kind == .otherInput ? 0 : event.keyCode,
            timestamp: event.timestamp,
            carbonModifiers: GlobalShortcut.carbonModifiers(from: event.modifierFlags)
        )
    }
}

/// A lone modifier fires only after release. Other input while it is down
/// makes the gesture part of a normal keyboard or mouse shortcut instead.
struct ModifierTapTracker {
    private(set) var candidate: UInt16?

    mutating func reset() { candidate = nil }

    mutating func release(in sample: KeyboardEventSample, configuredKeys: Set<UInt16>) -> UInt16? {
        guard sample.kind == .flagsChanged else {
            candidate = nil
            return nil
        }
        guard let flag = GlobalShortcut.modifierFlag(for: sample.keyCode) else {
            candidate = nil
            return nil
        }
        let modifier = GlobalShortcut.carbonModifiers(from: flag)
        if candidate == sample.keyCode {
            candidate = nil
            return sample.carbonModifiers & modifier == 0 ? sample.keyCode : nil
        }
        candidate = configuredKeys.contains(sample.keyCode)
            && sample.carbonModifiers == modifier
            && !sample.functionIsPressed ? sample.keyCode : nil
        return nil
    }
}

enum FnReleaseAction: Equatable {
    case ignore
    case finishAgent
    case finishDictation
    case registerQuickTap
}

private let hotKeyEventCallback: EventHandlerUPP = { _, event, userInfo in
    guard let event, let userInfo else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let result = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard result == noErr else { return result }

    let controller = Unmanaged<ShortcutController>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async {
        controller.handleHotKey(id: hotKeyID.id)
    }
    return noErr
}

/// Owns the configurable system-wide shortcuts and the Fn gesture state machine.
/// Carbon hot keys need no permission. Fn and modifier taps use AppKit event
/// monitors and the Accessibility permission that text insertion already requires.
final class ShortcutController: @unchecked Sendable {
    private weak var appState: AppState?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeys: [GlobalShortcutAction: EventHotKeyRef] = [:]
    private var failedHotKeys: [GlobalShortcutAction] = []
    private var hotKeysPaused = false
    private var wakeObserver: NSObjectProtocol?

    private var fnIsDown = false
    private var fnWasChorded = false
    private var firstTapAt: TimeInterval?
    private var holdTask: Task<Void, Never>?
    private var singleTapTask: Task<Void, Never>?
    private var gestureMonitorReady = false
    private var modifierTap = ModifierTapTracker()
    private var pendingModifierTap: (keyCode: UInt16, timestamp: TimeInterval, startedInput: Bool)?
    private var pendingModifierTask: Task<Void, Never>?

    private static let doubleTapInterval: TimeInterval = 0.45
    private let holdThreshold = Duration.milliseconds(150)
    private let hotKeySignature: OSType = 0x534B_4B55 // SKKU

    @MainActor
    init(appState: AppState) {
        self.appState = appState
    }

    deinit {
        stop()
    }

    @MainActor
    func start() {
        reloadHotKeys()
        installGestureMonitors()
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.installGestureMonitors() }
            }
        }
    }

    func stop() {
        holdTask?.cancel()
        singleTapTask?.cancel()
        pendingModifierTask?.cancel()

        removeGestureMonitors()

        unregisterHotKeys()
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
            self.hotKeyHandler = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    @MainActor
    func refreshAccessibilityPermission() {
        installGestureMonitors()
    }

    @MainActor
    fileprivate func handleHotKey(id: UInt32) {
        guard let appState else { return }
        firstTapAt = nil
        singleTapTask?.cancel()
        switch GlobalShortcutAction(rawValue: id) {
        case .voiceInput:
            appState.workflow.toggleDictation()
        case .voiceAgent:
            appState.workflow.startAgent()
        case nil:
            break
        }
    }

    @MainActor
    func handle(_ sample: KeyboardEventSample) {
        guard let appState else { return }

        let modifierKeys = Set(GlobalShortcutAction.allCases.compactMap { action -> UInt16? in
            guard let shortcut = appState.settings.globalShortcut(for: action), shortcut.isModifierOnly else { return nil }
            return UInt16(shortcut.keyCode)
        })
        if hotKeysPaused {
            modifierTap.reset()
        } else if let keyCode = modifierTap.release(in: sample, configuredKeys: modifierKeys) {
            handleModifierTap(keyCode, at: sample.timestamp, appState: appState)
            return
        }

        let isFnKey = sample.keyCode == UInt16(kVK_Function)

        if sample.kind == .keyDown,
           Self.shouldCancelForEscape(
               keyCode: sample.keyCode,
               dictationIsCancellable: appState.workflow.dictationPhase.isCancellable || appState.workflow.dictationIsListening,
               agentIsCancellable: appState.workflow.agentPhase.isCancellable || appState.workflow.agentIsListening
           ) {
            holdTask?.cancel()
            singleTapTask?.cancel()
            pendingModifierTask?.cancel()
            pendingModifierTask = nil
            pendingModifierTap = nil
            firstTapAt = nil
            fnWasChorded = fnIsDown
            appState.workflow.cancelActiveVoiceWorkflow()
            return
        }

        if sample.kind == .keyDown, fnIsDown, !isFnKey {
            fnWasChorded = true
            holdTask?.cancel()
            if appState.workflow.dictationIsListening {
                appState.workflow.cancelDictation()
            }
            return
        }

        guard sample.kind == .flagsChanged else { return }

        if sample.functionIsPressed, !fnIsDown {
            fnDown(appState)
        } else if !sample.functionIsPressed, fnIsDown {
            fnUp(appState, at: sample.timestamp)
        }
    }

    @MainActor
    private func handleModifierTap(_ keyCode: UInt16, at timestamp: TimeInterval, appState: AppState) {
        func action(for key: UInt16, tapCount: UInt8) -> GlobalShortcutAction? {
            GlobalShortcutAction.allCases.first {
                guard let shortcut = appState.settings.globalShortcut(for: $0) else { return false }
                return shortcut.isModifierOnly && shortcut.keyCode == UInt32(key)
                    && shortcut.modifierTapCount == tapCount
            }
        }

        let singleAction = action(for: keyCode, tapCount: 1)
        let doubleAction = action(for: keyCode, tapCount: 2)
        guard singleAction != nil || doubleAction != nil else { return }

        if let pendingModifierTap,
           pendingModifierTap.keyCode == keyCode,
           timestamp >= pendingModifierTap.timestamp,
           timestamp - pendingModifierTap.timestamp <= Self.doubleTapInterval,
           let doubleAction {
            pendingModifierTask?.cancel()
            pendingModifierTask = nil
            self.pendingModifierTap = nil
            if !(pendingModifierTap.startedInput && doubleAction == .voiceAgent
                 && appState.workflow.promoteFnTapToAgent()) {
                handleHotKey(id: doubleAction.rawValue)
            }
            return
        }

        if let pendingModifierTap {
            pendingModifierTask?.cancel()
            self.pendingModifierTap = nil
            if pendingModifierTap.startedInput {
                appState.workflow.confirmFnTapDictation()
            } else if let previousAction = action(for: pendingModifierTap.keyCode, tapCount: 1),
                      !appState.workflow.agentIsListening {
                handleHotKey(id: previousAction.rawValue)
            }
        }

        if let singleAction, doubleAction == nil {
            handleHotKey(id: singleAction.rawValue)
            return
        }

        let startsInputImmediately = singleAction == .voiceInput && doubleAction == .voiceAgent
            && !appState.workflow.agentIsListening
        if startsInputImmediately {
            if appState.workflow.dictationIsListening {
                handleHotKey(id: GlobalShortcutAction.voiceInput.rawValue)
                return
            }
            appState.workflow.startFnTapDictation()
        }

        pendingModifierTask?.cancel()
        pendingModifierTap = (keyCode, timestamp, startsInputImmediately)
        pendingModifierTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled, self.pendingModifierTap?.keyCode == keyCode else { return }
            self.pendingModifierTap = nil
            self.pendingModifierTask = nil
            if startsInputImmediately {
                appState.workflow.confirmFnTapDictation()
            } else if let singleAction, !appState.workflow.agentIsListening {
                self.handleHotKey(id: singleAction.rawValue)
            }
        }
    }

    @MainActor
    private func fnDown(_ appState: AppState) {
        fnIsDown = true
        fnWasChorded = false

        guard Self.shouldArmHold(appState) else { return }
        holdTask?.cancel()
        holdTask = Task { @MainActor [weak self, weak appState] in
            try? await Task.sleep(for: self?.holdThreshold ?? .milliseconds(150))
            guard let self, let appState, !Task.isCancelled, self.fnIsDown, !self.fnWasChorded,
                  ShortcutController.shouldArmHold(appState) else { return }
            self.firstTapAt = nil
            self.singleTapTask?.cancel()
            appState.workflow.startDictation()
        }
    }

    @MainActor
    private func fnUp(_ appState: AppState, at timestamp: TimeInterval) {
        fnIsDown = false
        holdTask?.cancel()
        let wasChorded = fnWasChorded
        fnWasChorded = false

        if Self.isDoubleTap(first: firstTapAt, second: timestamp, wasChorded: wasChorded),
           (appState.workflow.canPromoteFnTap
                || (!appState.workflow.dictationIsListening && !appState.workflow.agentIsListening)) {
            firstTapAt = nil
            singleTapTask?.cancel()
            if !appState.workflow.promoteFnTapToAgent() { appState.workflow.startAgent() }
            return
        }

        switch Self.releaseAction(
            wasChorded: wasChorded,
            agentIsListening: appState.workflow.agentIsListening,
            dictationIsListening: appState.workflow.dictationIsListening
        ) {
        case .ignore:
            firstTapAt = nil
            singleTapTask?.cancel()
        case .finishAgent:
            firstTapAt = nil
            singleTapTask?.cancel()
            appState.workflow.finishAgentListening()
        case .finishDictation:
            firstTapAt = nil
            singleTapTask?.cancel()
            appState.workflow.finishDictation()
        case .registerQuickTap:
            registerQuickTap(appState, at: timestamp)
        }
    }

    static func isDoubleTap(first: TimeInterval?, second: TimeInterval, wasChorded: Bool) -> Bool {
        guard !wasChorded, let first else { return false }
        return second >= first && second - first <= doubleTapInterval
    }

    /// A hold never starts dictation over a listening workflow; releasing Fn finishes that one instead.
    static func shouldArmHold(inputMode: InputMode, agentIsListening: Bool, dictationIsListening: Bool) -> Bool {
        inputMode == .hold && !agentIsListening && !dictationIsListening
    }

    @MainActor
    private static func shouldArmHold(_ appState: AppState) -> Bool {
        shouldArmHold(
            inputMode: appState.settings.inputMode,
            agentIsListening: appState.workflow.agentIsListening,
            dictationIsListening: appState.workflow.dictationIsListening
        )
    }

    /// The monitor only observes Esc, so the key still reaches the frontmost app. Reacting only
    /// while recording or processing keeps an Esc meant for that app from closing a finished card.
    static func shouldCancelForEscape(
        keyCode: UInt16,
        dictationIsCancellable: Bool,
        agentIsCancellable: Bool
    ) -> Bool {
        keyCode == UInt16(kVK_Escape) && (dictationIsCancellable || agentIsCancellable)
    }

    static func releaseAction(
        wasChorded: Bool,
        agentIsListening: Bool,
        dictationIsListening: Bool
    ) -> FnReleaseAction {
        if wasChorded { return .ignore }
        if agentIsListening { return .finishAgent }
        if dictationIsListening { return .finishDictation }
        return .registerQuickTap
    }

    @MainActor
    private func registerQuickTap(_ appState: AppState, at timestamp: TimeInterval) {
        firstTapAt = timestamp
        singleTapTask?.cancel()
        guard appState.settings.inputMode == .tap else { return }

        appState.workflow.startFnTapDictation()

        singleTapTask = Task { @MainActor [weak self, weak appState] in
            try? await Task.sleep(for: .seconds(Self.doubleTapInterval))
            guard let self, let appState, !Task.isCancelled, self.firstTapAt == timestamp else { return }
            appState.workflow.confirmFnTapDictation()
        }
    }

    @MainActor
    private func installGestureMonitors() {
        let rebuilding = globalKeyMonitor != nil || localKeyMonitor != nil
        removeGestureMonitors()

        // Do not install a global keyboard monitor before Accessibility is
        // already trusted. This keeps startup entirely outside Input Monitoring.
        guard AXIsProcessTrusted() else {
            Log.shortcut.info("Gesture monitors not installed: Accessibility not granted")
            gestureMonitorReady = false
            publishStatus()
            return
        }

        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.receiveGestureEvent(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.receiveGestureEvent(event)
            return event
        }
        gestureMonitorReady = globalKeyMonitor != nil && localKeyMonitor != nil
        let ready = gestureMonitorReady
        let change = rebuilding ? "rebuilt" : "installed"
        Log.shortcut.log(
            level: ready ? .info : .error,
            "Gesture monitors \(change, privacy: .public), ready: \(ready, privacy: .public)"
        )
        publishStatus()
    }

    private func removeGestureMonitors() {
        modifierTap.reset()
        pendingModifierTask?.cancel()
        pendingModifierTask = nil
        pendingModifierTap = nil
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        gestureMonitorReady = false
    }

    private func receiveGestureEvent(_ event: NSEvent) {
        guard let sample = KeyboardEventSample.from(event) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handle(sample)
        }
    }

    /// Registers the shortcuts from current settings. An enabled shortcut that fails
    /// to register is reported as a conflict.
    @MainActor
    func reloadHotKeys() {
        unregisterHotKeys()
        // Paused while settings records a shortcut; keep the last status meanwhile.
        guard !hotKeysPaused, let appState else { return }

        let handlerReady = installHotKeyHandlerIfNeeded()
        var failed: [GlobalShortcutAction] = []
        for action in GlobalShortcutAction.allCases {
            guard let shortcut = appState.settings.globalShortcut(for: action) else { continue }
            if shortcut.isModifierOnly { continue }
            if handlerReady, let hotKey = register(shortcut, for: action) {
                hotKeys[action] = hotKey
            } else {
                failed.append(action)
            }
        }
        failedHotKeys = failed
        publishStatus()
    }

    @MainActor
    func setHotKeysPaused(_ paused: Bool) {
        guard hotKeysPaused != paused else { return }
        hotKeysPaused = paused
        modifierTap.reset()
        pendingModifierTask?.cancel()
        pendingModifierTask = nil
        pendingModifierTap = nil
        reloadHotKeys()
    }

    static func status(gestureReady: Bool, failedHotKeys: [GlobalShortcutAction]) -> AppState.ShortcutStatus {
        if !failedHotKeys.isEmpty { return .hotKeyConflict(failedHotKeys) }
        return gestureReady ? .ready : .accessibilityRequired
    }

    @MainActor
    private func installHotKeyHandlerIfNeeded() -> Bool {
        guard hotKeyHandler == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )
        if status != noErr {
            Log.shortcut.error("Carbon hot key handler failed to install: OSStatus \(status, privacy: .public)")
        }
        return status == noErr
    }

    @MainActor
    private func register(_ shortcut: GlobalShortcut, for action: GlobalShortcutAction) -> EventHotKeyRef? {
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            EventHotKeyID(signature: hotKeySignature, id: action.rawValue),
            GetApplicationEventTarget(),
            // Exclusive registration fails when another app already registered the
            // same combination, which is how conflicts surface in settings.
            OptionBits(kEventHotKeyExclusive),
            &hotKey
        )
        if status != noErr {
            let keys = shortcut.displayString
            let name = String(describing: action)
            Log.shortcut.error(
                "Carbon hot key \(keys, privacy: .public) for \(name, privacy: .public) failed: OSStatus \(status, privacy: .public)"
            )
        }
        return status == noErr ? hotKey : nil
    }

    private func unregisterHotKeys() {
        for hotKey in hotKeys.values { UnregisterEventHotKey(hotKey) }
        hotKeys.removeAll()
    }

    @MainActor
    private func publishStatus() {
        appState?.shortcutStatus = Self.status(gestureReady: gestureMonitorReady, failedHotKeys: failedHotKeys)
    }
}

extension AppState {
    enum ShortcutStatus: Equatable {
        case starting, ready, accessibilityRequired
        /// Enabled shortcuts that could not be registered, usually because another app owns them.
        case hotKeyConflict([GlobalShortcutAction])
        var symbol: String {
            switch self {
            case .starting: "clock"
            case .ready: "checkmark.circle"
            case .accessibilityRequired, .hotKeyConflict: "exclamationmark.triangle"
            }
        }
        @MainActor func title(_ appState: AppState) -> String {
            let shortcutsOff = GlobalShortcutAction.allCases.allSatisfy { appState.settings.globalShortcut(for: $0) == nil }
            switch self {
            case .starting:
                return localized("Starting shortcuts…")
            case .ready:
                return shortcutsOff
                    ? localized("Fn ready · Global shortcuts off")
                    : localized("Fn and global shortcuts ready")
            case .accessibilityRequired:
                return shortcutsOff
                    ? localized("Fn needs Accessibility · Global shortcuts off")
                    : GlobalShortcutAction.allCases.contains(where: {
                        appState.settings.globalShortcut(for: $0)?.isModifierOnly == true
                    })
                        ? localized("Fn and single-modifier shortcuts need Accessibility")
                        : localized("Global shortcuts ready · Fn needs Accessibility")
            case .hotKeyConflict(let actions):
                guard actions.count == 1, let action = actions.first else {
                    return localized("Both global shortcuts are already in use by other apps. Record new ones.")
                }
                let keys = appState.settings.globalShortcut(for: action)?.displayString ?? ""
                return localized("\(keys) for \(action.title) is already in use by another app. Record a new one.")
            }
        }
    }
}
