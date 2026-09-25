import Foundation
import Observation

/// Preferences saved in UserDefaults, and the Qwen API Key saved in the Keychain.
/// Side effects on other objects go through the change handlers, which `AppState` sets.
@MainActor
@Observable
final class AppSettings {
    /// Saved as this app's `AppleLanguages`, which macOS applies at the next launch.
    var appLanguage: AppLanguage = .saved { didSet { appLanguage.save() } }
    var inputMode: InputMode = .hold { didSet { defaults.set(inputMode.rawValue, forKey: Keys.inputMode) } }
    var overlayPlacement: OverlayPlacement = .bottom {
        didSet { defaults.set(overlayPlacement.rawValue, forKey: Keys.overlayPlacement) }
    }
    var autoStop = false { didSet { defaults.set(autoStop, forKey: Keys.autoStop) } }
    var recognitionLanguage: RecognitionLanguage = .automatic {
        didSet { defaults.set(recognitionLanguage.rawValue, forKey: Keys.recognitionLanguage) }
    }
    var dictationNumberFormat: DictationNumberFormat = .preferDigits {
        didSet { defaults.set(dictationNumberFormat.rawValue, forKey: Keys.dictationNumberFormat) }
    }
    var dictationCleanup: DictationCleanup = .light {
        didSet { defaults.set(dictationCleanup.rawValue, forKey: Keys.dictationCleanup) }
    }
    var matchAppTone = true { didSet { defaults.set(matchAppTone, forKey: Keys.matchAppTone) } }
    var selectedDomains: Set<DomainPreset> = [] {
        didSet { defaults.set(selectedDomains.map(\.rawValue).sorted(), forKey: Keys.selectedDomains) }
    }
    var didCompleteOnboarding = false {
        didSet { defaults.set(didCompleteOnboarding, forKey: Keys.didCompleteOnboarding) }
    }
    var continuousConversation = true { didSet { defaults.set(continuousConversation, forKey: Keys.continuousConversation) } }
    var automaticAgentWriteBack = true {
        didSet { defaults.set(automaticAgentWriteBack, forKey: Keys.automaticAgentWriteBack) }
    }
    /// Nil until the user picks an engine, so the default keeps following the region.
    private var storedSearchEngine: SearchEngine? = nil {
        didSet { defaults.set(storedSearchEngine?.rawValue, forKey: Keys.searchEngine) }
    }
    var searchEngine: SearchEngine {
        get { storedSearchEngine ?? SearchEngine.defaultEngine(for: qwenRegion) }
        set { storedSearchEngine = newValue }
    }
    var learnFromCorrections = true { didSet { defaults.set(learnFromCorrections, forKey: Keys.learnCorrections) } }
    var soundCuesEnabled = true { didSet { defaults.set(soundCuesEnabled, forKey: Keys.soundCues) } }
    var selectedTextAllowed = true { didSet { defaults.set(selectedTextAllowed, forKey: Keys.selectedText) } }
    var currentAppAllowed = true { didSet { defaults.set(currentAppAllowed, forKey: Keys.currentApp) } }
    var windowTitleAllowed = true { didSet { defaults.set(windowTitleAllowed, forKey: Keys.windowTitle) } }
    var clipboardAllowed = false { didSet { defaults.set(clipboardAllowed, forKey: Keys.clipboard) } }
    var browserPageAllowed = false { didSet { defaults.set(browserPageAllowed, forKey: Keys.browserPage) } }
    var screenTextAllowed = true { didSet { defaults.set(screenTextAllowed, forKey: Keys.screenText) } }
    var historyRetention: HistoryRetention = .days30 {
        didSet { defaults.set(historyRetention.rawValue, forKey: Keys.historyRetention); historyRetentionChangeHandler?() }
    }
    var storeVoiceAudio = true { didSet { defaults.set(storeVoiceAudio, forKey: Keys.storeVoiceAudio) } }
    private(set) var showInMenuBar = true { didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) } }
    var hideDockIconAfterMainWindowCloses = false {
        didSet {
            defaults.set(hideDockIconAfterMainWindowCloses, forKey: Keys.hideDockIconAfterMainWindowCloses)
            if hideDockIconAfterMainWindowCloses { showInMenuBar = true }
        }
    }
    var qwenRegion: QwenRegion = .beijing {
        didSet { defaults.set(qwenRegion.rawValue, forKey: Keys.qwenRegion); qwenConnectionChangeHandler?() }
    }
    var qwenWorkspaceID = "" {
        didSet { defaults.set(qwenWorkspaceID, forKey: Keys.qwenWorkspace); qwenConnectionChangeHandler?() }
    }
    var realtimeModel = QwenModelCatalog.defaultRealtimeModel {
        didSet { defaults.set(realtimeModel, forKey: Keys.realtimeModel); qwenConnectionChangeHandler?() }
    }
    var reasoningModel = QwenModelCatalog.defaultReasoningModel {
        didSet { defaults.set(reasoningModel, forKey: Keys.reasoningModel); qwenConnectionChangeHandler?() }
    }
    /// The saved key; edits stay in a view draft until `commitQwenCredentials` runs.
    private(set) var apiKey = ""
    // nil means the shortcut is turned off; Fn gestures keep working either way.
    var voiceInputShortcut: GlobalShortcut? = .defaultVoiceInput {
        didSet { saveGlobalShortcut(voiceInputShortcut, forKey: Keys.voiceInputShortcut) }
    }
    var voiceAgentShortcut: GlobalShortcut? = .defaultVoiceAgent {
        didSet { saveGlobalShortcut(voiceAgentShortcut, forKey: Keys.voiceAgentShortcut) }
    }

    /// The API Key, region, Workspace ID or a model changed.
    @ObservationIgnored var qwenConnectionChangeHandler: (@MainActor () -> Void)?
    @ObservationIgnored var historyRetentionChangeHandler: (@MainActor () -> Void)?
    @ObservationIgnored var globalShortcutChangeHandler: (@MainActor () -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainStore

    init(defaults: UserDefaults, keychain: KeychainStore) {
        self.defaults = defaults
        self.keychain = keychain
        loadSettings()
        apiKey = (try? keychain.string(for: Keys.apiKey)) ?? ""
    }

    var configuration: QwenConfiguration {
        QwenConfiguration(region: qwenRegion, workspaceID: qwenWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines), realtimeModel: realtimeModel, reasoningModel: reasoningModel)
    }

    func setShowInMenuBar(_ isVisible: Bool) {
        guard isVisible || !hideDockIconAfterMainWindowCloses else { return }
        showInMenuBar = isVisible
    }

    func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { try keychain.remove(Keys.apiKey) }
        else { try keychain.set(trimmed, for: Keys.apiKey) }
        apiKey = trimmed
        qwenConnectionChangeHandler?()
    }

    private func saveGlobalShortcut(_ shortcut: GlobalShortcut?, forKey key: String) {
        defaults.set(shortcut?.storageValue ?? "", forKey: key)
        globalShortcutChangeHandler?()
    }

    /// Set once the user dismisses the notice about data left by earlier encrypted builds.
    var legacyDataNoticeDismissed: Bool {
        get { defaults.bool(forKey: Keys.legacyDataNoticeDismissed) }
        set { defaults.set(newValue, forKey: Keys.legacyDataNoticeDismissed) }
    }

    /// Custom words earlier builds kept in defaults, removed as they are read; nil when there are none.
    func takeLegacyCustomTerms() -> [String]? {
        guard let terms = defaults.stringArray(forKey: Keys.legacyCustomTerms) else { return nil }
        defaults.removeObject(forKey: Keys.legacyCustomTerms)
        return terms
    }

    private func loadSettings() {
        if let raw = defaults.string(forKey: Keys.inputMode),
           let value = InputMode(rawValue: raw) ?? InputMode.legacyRawValues[raw] { inputMode = value }
        if let raw = defaults.string(forKey: Keys.overlayPlacement),
           let value = OverlayPlacement(rawValue: raw) { overlayPlacement = value }
        // The language now lives in `AppleLanguages`; carry an explicit old choice over once.
        if let raw = defaults.string(forKey: Keys.legacyLanguage) {
            if appLanguage == .system, let language = AppLanguage(rawValue: raw) { appLanguage = language }
            defaults.removeObject(forKey: Keys.legacyLanguage)
        }
        if let raw = defaults.string(forKey: Keys.recognitionLanguage),
           let value = RecognitionLanguage(rawValue: raw) { recognitionLanguage = value }
        if let raw = defaults.string(forKey: Keys.dictationNumberFormat),
           let value = DictationNumberFormat(rawValue: raw) { dictationNumberFormat = value }
        if let raw = defaults.string(forKey: Keys.dictationCleanup),
           let value = DictationCleanup(rawValue: raw) { dictationCleanup = value }
        selectedDomains = Set((defaults.stringArray(forKey: Keys.selectedDomains) ?? []).compactMap(DomainPreset.init(rawValue:)))
        didCompleteOnboarding = defaults.bool(forKey: Keys.didCompleteOnboarding)
        if let raw = defaults.string(forKey: Keys.historyRetention), let value = HistoryRetention(rawValue: raw) { historyRetention = value }
        if let raw = defaults.string(forKey: Keys.qwenRegion), let value = QwenRegion(rawValue: raw) { qwenRegion = value }
        qwenWorkspaceID = defaults.string(forKey: Keys.qwenWorkspace) ?? ""
        // One-time move from the old 3.5 default to 3.8; afterwards an explicit 3.5 choice sticks.
        realtimeModel = QwenModelCatalog.realtimeModel(
            stored: defaults.string(forKey: Keys.realtimeModel),
            upgradesPreviousDefault: !defaults.bool(forKey: Keys.realtimeModelUpgraded)
        )
        defaults.set(true, forKey: Keys.realtimeModelUpgraded)
        reasoningModel = QwenModelCatalog.reasoningModel(stored: defaults.string(forKey: Keys.reasoningModel))
        storedSearchEngine = defaults.string(forKey: Keys.searchEngine).flatMap(SearchEngine.init(rawValue:))
        autoStop = storedBool(Keys.autoStop, default: false)
        matchAppTone = storedBool(Keys.matchAppTone, default: true)
        continuousConversation = storedBool(Keys.continuousConversation, default: true)
        automaticAgentWriteBack = storedBool(Keys.automaticAgentWriteBack, default: true)
        learnFromCorrections = storedBool(Keys.learnCorrections, default: true)
        soundCuesEnabled = storedBool(Keys.soundCues, default: true)
        selectedTextAllowed = storedBool(Keys.selectedText, default: true)
        currentAppAllowed = storedBool(Keys.currentApp, default: true)
        windowTitleAllowed = storedBool(Keys.windowTitle, default: true)
        clipboardAllowed = defaults.bool(forKey: Keys.clipboard)
        browserPageAllowed = defaults.bool(forKey: Keys.browserPage)
        screenTextAllowed = storedBool(Keys.screenText, default: true)
        storeVoiceAudio = storedBool(Keys.storeVoiceAudio, default: true)
        showInMenuBar = storedBool(Keys.showInMenuBar, default: true)
        hideDockIconAfterMainWindowCloses = storedBool(Keys.hideDockIconAfterMainWindowCloses, default: false)
        // Earlier builds hard-coded ⇧⌘D / ⇧⌘A without saving them, so upgrades start from the new defaults.
        if let raw = defaults.string(forKey: Keys.voiceInputShortcut) {
            voiceInputShortcut = GlobalShortcut.restored(from: raw, fallback: .defaultVoiceInput)
        }
        if let raw = defaults.string(forKey: Keys.voiceAgentShortcut) {
            voiceAgentShortcut = GlobalShortcut.restored(from: raw, fallback: .defaultVoiceAgent)
        }
    }

    /// The saved flag, or `fallback` when it was never saved.
    private func storedBool(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private enum Keys {
        static let inputMode = "inputMode", legacyLanguage = "appLanguage", autoStop = "autoStop"
        static let overlayPlacement = "overlay.placement"
        static let recognitionLanguage = "dictation.recognitionLanguage", dictationNumberFormat = "dictation.numberFormat"
        static let dictationCleanup = "dictation.cleanup", soundCues = "voice.soundCues"
        static let matchAppTone = "dictation.matchAppTone"
        static let selectedDomains = "dictation.selectedDomains", legacyCustomTerms = "dictation.customDomainTerms"
        static let didCompleteOnboarding = "onboarding.completed"
        static let continuousConversation = "continuousConversation", learnCorrections = "learnFromCorrections"
        static let automaticAgentWriteBack = "agent.automaticWriteBack", searchEngine = "agent.searchEngine"
        static let selectedText = "privacy.selectedText", currentApp = "privacy.currentApp", windowTitle = "privacy.windowTitle"
        static let clipboard = "privacy.clipboard", browserPage = "privacy.browserPage", screenText = "privacy.screenText"
        static let historyRetention = "historyRetention", storeVoiceAudio = "storeVoiceAudio", showInMenuBar = "showInMenuBar"
        static let hideDockIconAfterMainWindowCloses = "hideDockIconAfterMainWindowCloses"
        static let legacyDataNoticeDismissed = "history.legacyDataNoticeDismissed"
        static let qwenRegion = "qwen.region", qwenWorkspace = "qwen.workspace", realtimeModel = "qwen.realtimeModel"
        static let reasoningModel = "qwen.reasoningModel", apiKey = "qwen.apiKey"
        static let voiceInputShortcut = "shortcuts.voiceInput", voiceAgentShortcut = "shortcuts.voiceAgent"
        static let realtimeModelUpgraded = "qwen.realtimeModelUpgradedToQwen38"
    }
}

enum InputMode: String, CaseIterable, Identifiable {
    case hold, tap
    var id: String { rawValue }

    /// Earlier builds saved the Chinese labels as raw values.
    static let legacyRawValues: [String: InputMode] = ["按住 Fn": .hold, "单击 Fn": .tap]

    var title: String {
        switch self {
        case .hold: localized("Hold Fn")
        case .tap: localized("Tap Fn")
        }
    }
}

/// The interface language, kept in this app's `AppleLanguages` so macOS localizes its own menus,
/// alerts and date formats to match. macOS reads it only at launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, chinese, english
    var id: String { rawValue }

    private static let key = "AppleLanguages"

    /// Language names stay in their own language.
    var title: String {
        switch self {
        case .system: localized("System Default")
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    /// Reads only this app's domain: `UserDefaults.standard.object(forKey:)` also returns the system-wide list.
    static var saved: AppLanguage {
        let domain = Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:))
        return AppLanguage(appleLanguages: domain?[key] as? [String])
    }

    /// An override set elsewhere, such as in System Settings, reads as System Default unless it matches a choice.
    init(appleLanguages: [String]?) {
        switch appleLanguages?.first {
        case let language? where language.hasPrefix("zh-Hans"): self = .chinese
        case let language? where language.hasPrefix("en"): self = .english
        default: self = .system
        }
    }

    var appleLanguages: [String]? {
        switch self {
        case .system: nil
        case .chinese: ["zh-Hans"]
        case .english: ["en"]
        }
    }

    func save() {
        if let appleLanguages {
            UserDefaults.standard.set(appleLanguages, forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }
}
