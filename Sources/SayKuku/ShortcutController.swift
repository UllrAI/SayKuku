import ApplicationServices
import AppKit
import Carbon.HIToolbox

private struct KeyboardEventSample: Sendable {
    enum Kind: Sendable {
        case flagsChanged
        case keyDown
    }

    let kind: Kind
    let functionIsPressed: Bool
    let keyCode: UInt16
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
/// Carbon hot keys need no permission. Fn uses AppKit event monitors and the
/// Accessibility permission that text insertion already requires.
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
    private var firstTapAt: ContinuousClock.Instant?
    private var holdTask: Task<Void, Never>?
    private var singleTapTask: Task<Void, Never>?
    private var fnMonitorReady = false

    private let doubleTapInterval = Duration.milliseconds(275)
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
        installFnMonitors()
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.installFnMonitors() }
            }
        }
    }

    func stop() {
        holdTask?.cancel()
        singleTapTask?.cancel()

        removeFnMonitors()

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
        installFnMonitors()
    }

    @MainActor
    fileprivate func handleHotKey(id: UInt32) {
        guard let appState else { return }
        switch GlobalShortcutAction(rawValue: id) {
        case .voiceInput:
            appState.toggleDictation()
        case .voiceAgent:
            appState.startAgent()
        case nil:
            break
        }
    }

    @MainActor
    fileprivate func handle(_ sample: KeyboardEventSample) {
        guard let appState else { return }

        let isFnKey = sample.keyCode == UInt16(kVK_Function)

        if sample.kind == .keyDown,
           Self.shouldCancelForEscape(
               keyCode: sample.keyCode,
               dictationIsActive: appState.dictationPhase != .idle,
               agentIsActive: appState.agentPhase != .hidden
           ) {
            holdTask?.cancel()
            singleTapTask?.cancel()
            firstTapAt = nil
            fnWasChorded = fnIsDown
            appState.cancelActiveVoiceWorkflow()
            return
        }

        if sample.kind == .keyDown, fnIsDown, !isFnKey {
            fnWasChorded = true
            holdTask?.cancel()
            if appState.dictationPhase == .listening {
                appState.cancelDictation()
            }
            return
        }

        guard sample.kind == .flagsChanged else { return }

        if sample.functionIsPressed, !fnIsDown {
            fnDown(appState)
        } else if !sample.functionIsPressed, fnIsDown {
            fnUp(appState)
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
            appState.startDictation()
        }
    }

    @MainActor
    private func fnUp(_ appState: AppState) {
        fnIsDown = false
        holdTask?.cancel()
        let wasChorded = fnWasChorded
        fnWasChorded = false

        switch Self.releaseAction(
            wasChorded: wasChorded,
            agentIsListening: appState.agentPhase == .listening,
            dictationIsListening: appState.dictationPhase == .listening
        ) {
        case .ignore:
            firstTapAt = nil
            singleTapTask?.cancel()
        case .finishAgent:
            firstTapAt = nil
            singleTapTask?.cancel()
            appState.finishAgentListening()
        case .finishDictation:
            firstTapAt = nil
            singleTapTask?.cancel()
            appState.finishDictation()
        case .registerQuickTap:
            registerQuickTap(appState)
        }
    }

    /// A hold never starts dictation over a listening workflow; releasing Fn finishes that one instead.
    static func shouldArmHold(inputMode: InputMode, agentIsListening: Bool, dictationIsListening: Bool) -> Bool {
        inputMode == .hold && !agentIsListening && !dictationIsListening
    }

    @MainActor
    private static func shouldArmHold(_ appState: AppState) -> Bool {
        shouldArmHold(
            inputMode: appState.inputMode,
            agentIsListening: appState.agentPhase == .listening,
            dictationIsListening: appState.dictationPhase == .listening
        )
    }

    static func shouldCancelForEscape(
        keyCode: UInt16,
        dictationIsActive: Bool,
        agentIsActive: Bool
    ) -> Bool {
        keyCode == UInt16(kVK_Escape) && (dictationIsActive || agentIsActive)
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
    private func registerQuickTap(_ appState: AppState) {
        let now = ContinuousClock.now
        if let firstTapAt, now - firstTapAt <= doubleTapInterval {
            self.firstTapAt = nil
            singleTapTask?.cancel()
            appState.startAgent()
            return
        }

        firstTapAt = now
        singleTapTask?.cancel()
        guard appState.inputMode == .tap else { return }

        singleTapTask = Task { @MainActor [weak self, weak appState] in
            try? await Task.sleep(for: self?.doubleTapInterval ?? .milliseconds(275))
            guard let self, let appState, !Task.isCancelled else { return }
            self.firstTapAt = nil
            appState.startDictation()
        }
    }

    @MainActor
    private func installFnMonitors() {
        removeFnMonitors()

        // Do not install a global keyboard monitor before Accessibility is
        // already trusted. This keeps startup entirely outside Input Monitoring.
        guard AXIsProcessTrusted() else {
            fnMonitorReady = false
            publishStatus()
            return
        }

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.receiveFnEvent(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.receiveFnEvent(event)
            return event
        }
        fnMonitorReady = globalKeyMonitor != nil && localKeyMonitor != nil
        publishStatus()
    }

    private func removeFnMonitors() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        fnMonitorReady = false
    }

    private func receiveFnEvent(_ event: NSEvent) {
        let kind: KeyboardEventSample.Kind
        switch event.type {
        case .flagsChanged:
            kind = .flagsChanged
        case .keyDown:
            kind = .keyDown
        default:
            return
        }

        let sample = KeyboardEventSample(
            kind: kind,
            functionIsPressed: event.modifierFlags.contains(.function),
            keyCode: event.keyCode
        )
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
            guard let shortcut = appState.globalShortcut(for: action) else { continue }
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
        reloadHotKeys()
    }

    static func status(fnReady: Bool, failedHotKeys: [GlobalShortcutAction]) -> AppState.ShortcutStatus {
        if !failedHotKeys.isEmpty { return .hotKeyConflict(failedHotKeys) }
        return fnReady ? .ready : .accessibilityRequired
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
        return status == noErr ? hotKey : nil
    }

    private func unregisterHotKeys() {
        for hotKey in hotKeys.values { UnregisterEventHotKey(hotKey) }
        hotKeys.removeAll()
    }

    @MainActor
    private func publishStatus() {
        appState?.shortcutStatus = Self.status(fnReady: fnMonitorReady, failedHotKeys: failedHotKeys)
    }
}
