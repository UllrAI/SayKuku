import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        HStack(spacing: 0) {
            SettingsSidebar(selection: $appState.settingsSection)
                .frame(width: KukuLayout.sidebarWidth)

            Rectangle()
                .fill(KukuColor.separator)
                .frame(width: 1)
                .accessibilityHidden(true)

            KukuPageScroll {
                switch appState.settingsSection {
                case .general: GeneralSettings()
                case .voiceInput: VoiceInputSettings()
                case .voiceAgent: VoiceAgentSettings()
                case .history: HistorySettings()
                case .privacy: PrivacySettings()
                case .qwen: QwenSettings()
                }
            }
            // Each section opens at the top instead of at the last section's scroll offset.
            .id(appState.settingsSection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localized("Settings"))
                .font(.kuku(.title))
                .foregroundStyle(KukuColor.textPrimary)
                .padding(.top, KukuLayout.pageTop)
                .padding(.horizontal, KukuSpacing.lg)
                .padding(.bottom, KukuSpacing.xl)

            VStack(spacing: KukuSpacing.xs) {
                ForEach(SettingsSection.allCases) { section in
                    SidebarButton(
                        title: section.title,
                        symbol: section.symbol,
                        isSelected: selection == section
                    ) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, KukuSpacing.sm)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KukuColor.sidebar)
    }
}

private struct VoiceInputSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        SettingsStack(title: localized("Voice Input"), subtitle: localized("Types what you say, without changing what you mean.")) {
            KukuGroup(localized("Input gesture")) {
                ForEach(InputMode.allCases) { mode in
                    if mode != InputMode.allCases.first {
                        KukuDivider()
                    }
                    KukuChoiceRow(
                        title: mode.title,
                        caption: mode == .hold
                            ? localized("Hold briefly to start, release to insert. Esc cancels.")
                            : localized("Tap to start, tap again to insert. Esc cancels."),
                        isSelected: appState.settings.inputMode == mode
                    ) {
                        appState.settings.inputMode = mode
                    }
                }
                KukuDivider()
                KukuToggleRow(
                    title: localized("Play a sound when recording starts and stops"),
                    caption: localized("Also plays for Voice Agent"),
                    isOn: $settings.soundCuesEnabled
                )
            }

            KukuGroup(localized("Microphone test")) {
                MicrophoneTestPanel()
            }

            KukuGroup(localized("Stop & output")) {
                KukuToggleRow(title: localized("Stop after a pause"), caption: autoStopSubtitle, isOn: $settings.autoStop)
                KukuDivider()
                SettingsOptionRow(
                    title: localized("Recognition language"),
                    selection: $settings.recognitionLanguage
                ) { language in
                    language.title
                }
                KukuDivider()
                SettingsOptionRow(
                    title: localized("Number format"),
                    selection: $settings.dictationNumberFormat
                ) { format in
                    format.title
                }
                KukuDivider()
                SettingsOptionRow(
                    title: localized("Speech cleanup"),
                    selection: $settings.dictationCleanup
                ) { cleanup in
                    cleanup.title
                }
                Text(localized("Light cleanup removes fillers and accidental repeats. Verbatim keeps hesitations and repeats."))
                .font(.kuku(.subheadline))
                .foregroundStyle(KukuColor.textSecondary)
                .padding(.horizontal, KukuLayout.rowPadding)
                .padding(.bottom, KukuSpacing.md)
                KukuDivider()
                KukuToggleRow(
                    title: localized("Keep ending punctuation"),
                    caption: localized("When off, Voice Input removes a final period, question mark, or exclamation mark."),
                    isOn: $settings.keepEndingPunctuation
                )
                KukuDivider()
                KukuToggleRow(
                    title: localized("Match the app’s tone"),
                    caption: localized(
                        "Casual in chat, complete sentences in email and documents, no trailing punctuation in code. Sends the current app’s name along with your speech."
                    ),
                    isOn: $settings.matchAppTone
                )
                // Verbatim only adds punctuation, so there is no tone to adjust.
                .disabled(appState.settings.dictationCleanup == .verbatim)
            }

            DictationAppFormatsSettings()

            KukuGroup(localized("Recognition")) {
                KukuRow(localized("Domains"), caption: domainSummary) {
                    Button(localized("Edit…")) {
                        appState.showDomainOnboarding()
                        // Setup sheets are presented by the main window.
                        appState.showMainWindow()
                    }
                    .buttonStyle(.kukuSecondary)
                }
                // Many selected domains would otherwise stretch the row.
                .lineLimit(2)
                KukuDivider()
                KukuRow(localized("Memory"), caption: memorySummary) {
                    Button(localized("Open Memory")) {
                        appState.showMainWindow(destination: .memory)
                    }
                    .buttonStyle(.kukuSecondary)
                }
                KukuDivider()
                KukuToggleRow(
                    title: localized("Learn from corrections"),
                    caption: localized(
                        "After you fix a misheard word, SayKuku asks whether to remember it. Nothing is saved until you say yes."
                    ),
                    isOn: $settings.learnFromCorrections
                )
            }
        }
    }

    /// Pause detection runs on the realtime session, which needs a workspace ID.
    private var autoStopSubtitle: String {
        appState.settings.configuration.realtimeURL == nil
            ? localized("Requires a Workspace ID in Qwen Connection")
            : localized("Ends recording after about 1 second of silence")
    }

    private var domainSummary: String {
        let domains = DomainPreset.allCases
            .filter(appState.settings.selectedDomains.contains)
            .map { $0.title }
        return domains.isEmpty
            ? localized("None selected")
            : domains.joined(separator: localized(", "))
    }

    private var memorySummary: String {
        let count = appState.data.memoryEntities.count
        return localized("\(count) items")
    }
}

private struct VoiceAgentSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        SettingsStack(title: localized("Voice Agent"), subtitle: localized("Press Fn twice to write, edit, or ask by voice.")) {
            KukuGroup(localized("Interaction")) {
                KukuToggleRow(
                    title: localized("Continuous conversation"),
                    caption: localized("Remembers recent conversations in the same app for 30 minutes. Quitting SayKuku clears them."),
                    isOn: $settings.continuousConversation
                )
                KukuDivider()
                KukuToggleRow(
                    title: localized("Insert automatically"),
                    caption: localized(
                        "Puts results right into the text field you’re using. When off, they stay in the overlay for you to copy."
                    ),
                    isOn: $settings.automaticAgentWriteBack
                )
                KukuDivider()
                KukuRow(
                    localized("Search engine"),
                    caption: localized("Used when Voice Agent searches the web")
                ) {
                    KukuPicker(
                        localized("Search engine"),
                        options: SearchEngine.allCases,
                        selection: $settings.searchEngine,
                        label: { $0.title }
                    )
                }
            }
        }
    }
}

private struct PrivacySettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        SettingsStack(title: localized("What Voice Agent can use"), subtitle: localized("While you talk, the overlay shows what’s sent.")) {
            KukuGroup(localized("Allow access to")) {
                KukuToggleRow(title: localized("Selected text"), caption: localized("Used to rewrite or ask about the text you’ve selected"), isOn: $settings.selectedTextAllowed)
                KukuDivider()
                KukuToggleRow(title: localized("Current app"), caption: localized("Name of the app you’re using"), isOn: $settings.currentAppAllowed)
                KukuDivider()
                KukuToggleRow(title: localized("Window title"), caption: localized("Includes private windows"), isOn: $settings.windowTitleAllowed)
                KukuDivider()
                KukuToggleRow(title: localized("Clipboard"), caption: localized("Text on your clipboard, excluding passwords"), isOn: $settings.clipboardAllowed)
                KukuDivider()
                KukuToggleRow(title: localized("Browser page"), caption: localized("URL of the current Safari or Chrome page"), isOn: $settings.browserPageAllowed)
                KukuDivider()
                KukuToggleRow(
                    title: localized("Text on screen"),
                    caption: localized("Text visible in the current window, for commands like “reply to this” or “summarize this page”. Never from password fields or sensitive apps."),
                    isOn: $settings.screenTextAllowed
                )
            }
            KukuGroup(localized("Always off-limits")) {
                VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                    HStack(spacing: KukuSpacing.sm) {
                        KukuBadge(text: localized("Password fields"), symbol: "lock.fill")
                        KukuBadge(text: localized("Password managers"), symbol: "key.fill")
                    }
                    Text(localized(
                        "Password managers include 1Password, Bitwarden, LastPass, Dashlane, KeePassXC, Keychain Access, and Passwords."
                    ))
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
                }
                .padding(KukuLayout.rowPadding)
            }
            KukuGroup(localized("Usage statistics")) {
                KukuToggleRow(
                    title: localized("Share usage statistics"),
                    caption: localized("Sends a random installation ID, app version, completed actions, and text lengths. Umami estimates country from your IP address. Statistics never include text or audio."),
                    isOn: $settings.analyticsEnabled
                )
            }
        }
    }
}

private struct QwenSettings: View {
    @Environment(AppState.self) private var appState
    @State private var draft = QwenCredentialsDraft()

    var body: some View {
        @Bindable var settings = appState.settings
        SettingsStack(title: localized("Qwen Connection"), subtitle: localized("Connect Qwen and choose models for Voice Input and Voice Agent.")) {
            KukuGroup(localized("Connection")) {
                QwenConnectionForm(draft: $draft)
                KukuDivider()
                HStack(spacing: KukuSpacing.md) {
                    QwenConnectionStatus(draft: draft)
                    Spacer(minLength: KukuSpacing.md)
                    QwenConnectionButton(draft: draft)
                }
                .kukuRowFrame()
            }
            KukuGroup(localized("Models")) {
                ModelPickerRow(
                    title: localized("Voice Input"),
                    caption: localized("Real-time transcription"),
                    value: $settings.realtimeModel,
                    presets: QwenModelCatalog.realtimeModels
                )
                KukuDivider()
                ModelPickerRow(
                    title: localized("Voice Agent"),
                    caption: localized("Also used for Memory imports and retrying recordings"),
                    value: $settings.reasoningModel,
                    presets: QwenModelCatalog.reasoningModels
                )
            }
        }
    }
}

/// Region, API Key, and Workspace ID rows shared by Settings and the first-run setup sheet.
/// Like any macOS settings field, the key and Workspace ID apply when editing ends:
/// on Return, when focus moves on, or when the form goes away. There is no unsaved state to lose.
struct QwenConnectionForm: View {
    private enum Field { case apiKey, workspaceID }

    @Environment(AppState.self) private var appState
    @Binding var draft: QwenCredentialsDraft
    @FocusState private var focusedField: Field?

    var body: some View {
        @Bindable var settings = appState.settings
        VStack(alignment: .leading, spacing: 0) {
            KukuRow(
                localized("Region"),
                caption: localized("Must match where your API Key was created")
            ) {
                KukuPicker(
                    localized("Region"),
                    options: QwenRegion.allCases,
                    selection: $settings.qwenRegion,
                    label: { $0.title }
                )
            }
            KukuDivider()
            credentialRow(
                .apiKey,
                title: "API Key",
                caption: keyCaption,
                link: helpLink(localized("Get an API Key"), page: "get-api-key")
            ) {
                SecureField("sk-…", text: $draft.apiKey)
                    .disabled(appState.settings.apiKeyLoadState == .failed)
            }
            if appState.settings.apiKeyLoadState == .failed {
                KukuDivider()
                KukuRow(localized("Keychain access needs attention"), caption: localized("Couldn’t read the API Key from this Mac’s Keychain. Try again before editing it.")) {
                    Button(localized("Try Again")) { appState.settings.reloadAPIKey() }
                        .buttonStyle(.kukuSecondary)
                }
            }
            KukuDivider()
            credentialRow(
                .workspaceID,
                title: localized("Workspace ID"),
                caption: localized("Optional. Lets Voice Input transcribe as you speak instead of after you stop."),
                link: helpLink(localized("Find Your Workspace ID"), page: "obtain-the-app-id-and-workspace-id")
            ) {
                TextField("llm-…", text: $draft.workspaceID)
            }
        }
        .onChange(of: appState.settings.apiKey, initial: true) { _, saved in draft.apiKey = saved }
        .onChange(of: appState.settings.qwenWorkspaceID, initial: true) { _, saved in draft.workspaceID = saved }
        .onChange(of: focusedField) { commit() }
        .onDisappear(perform: commit)
    }

    private func credentialRow<Input: View>(
        _ field: Field,
        title: String,
        caption: String,
        link: KukuExternalLink,
        @ViewBuilder input: () -> Input
    ) -> some View {
        HStack(spacing: KukuSpacing.md) {
            VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                KukuRowLabel(title: title, caption: caption)
                link
            }
            Spacer(minLength: KukuSpacing.md)
            input()
                .focused($focusedField, equals: field)
                .kukuField(isFocused: focusedField == field)
                .frame(width: KukuLayout.pickerWidth)
                .accessibilityLabel(title)
                .onSubmit(commit)
        }
        .kukuRowFrame()
    }

    private var keyCaption: String {
        if appState.settings.apiKeyLoadState == .failed { return localized("API Key unavailable") }
        return appState.settings.apiKey.isEmpty
            ? localized("Stored in this Mac’s Keychain")
            : localized("Saved in this Mac’s Keychain")
    }

    private func helpLink(_ title: String, page: String) -> KukuExternalLink {
        KukuExternalLink(title: title, destination: URL(string: interfaceLanguage.languageCode == Locale.LanguageCode.chinese
            ? "https://help.aliyun.com/zh/model-studio/\(page)"
            : "https://www.alibabacloud.com/help/en/model-studio/\(page)")!)
    }

    private func commit() {
        appState.commitQwenCredentials(draft)
    }
}

/// The result of the last connection test, or a hint when there is nothing to test yet.
struct QwenConnectionStatus: View {
    @Environment(AppState.self) private var appState
    let draft: QwenCredentialsDraft

    private var font: Font { .kuku(.subheadline, weight: .medium) }

    var body: some View {
        testResult
            .lineLimit(3)
    }

    @ViewBuilder
    private var testResult: some View {
        if appState.settings.apiKeyLoadState == .failed {
            KukuStatusLabel(text: localized("Couldn’t read the API Key from this Mac’s Keychain. Try again before editing it."), tone: .danger, font: font)
        } else {
            switch appState.connectionState {
            // A success only counts for the values it tested; edits since then need a new test.
            case .connected(let realtime, let chat) where draft.matches(apiKey: appState.settings.apiKey, workspaceID: appState.settings.qwenWorkspaceID):
                KukuStatusLabel(text: connectedMessage(realtime: realtime, chat: chat), tone: .success, font: font)
            case .failed(let message):
                KukuStatusLabel(text: message, tone: .danger, font: font)
            case .testing:
                hint(localized("Connecting to Qwen…"))
            case .connected, .idle:
                if !draft.hasKey {
                    hint(localized("Add an API Key to test the connection"))
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(KukuColor.textSecondary)
    }

    private func connectedMessage(realtime: Int?, chat: Int) -> String {
        guard let realtime else {
            return localized(
                "Connected · Voice Agent \(chat) ms · Without a Workspace ID, Voice Input transcribes after you stop"
            )
        }
        return localized("Connected · Voice Input \(realtime) ms · Voice Agent \(chat) ms")
    }
}

/// Tests the connection, committing anything still being edited first.
struct QwenConnectionButton: View {
    @Environment(AppState.self) private var appState
    let draft: QwenCredentialsDraft
    var kind: KukuButtonStyle.Kind = .primary

    var body: some View {
        let isTesting = appState.connectionState == .testing
        Button(isTesting ? localized("Testing…") : localized("Test Connection")) {
            Task { await appState.testQwenConnection(draft) }
        }
        .buttonStyle(.kuku(kind))
        .disabled(isTesting || !draft.hasKey || appState.settings.apiKeyLoadState == .failed)
    }
}

private struct ModelPickerRow: View {
    let title: String
    let caption: String
    @Binding var value: String
    let presets: [String]
    @State private var customDraft: String?

    var body: some View {
        KukuRow(title, caption: caption) {
            if let draft = customDraft {
                KukuTextField(
                    prompt: localized("Model ID"),
                    text: Binding(get: { draft }, set: { customDraft = $0 }),
                    autoFocus: true,
                    onSubmit: applyCustomModel
                )
                .frame(width: KukuLayout.pickerWidth)
                .onExitCommand { customDraft = nil }
                // Leaving the page applies the typed ID, as with the other settings fields.
                .onDisappear(perform: applyCustomModel)
                Button(localized("Use"), action: applyCustomModel)
                    .buttonStyle(.kukuSecondary)
            } else {
                KukuPicker(
                    title,
                    options: QwenModelCatalog.options(presets, including: value),
                    selection: $value,
                    label: { $0 }
                ) {
                    Divider()
                    Button(localized("Custom…")) { customDraft = value }
                }
            }
        }
    }

    private func applyCustomModel() {
        let model = customDraft?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !model.isEmpty { value = model }
        customDraft = nil
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings

        SettingsStack(title: localized("General"), subtitle: localized("Language, permissions, startup, overlay, shortcuts, and updates.")) {
            KukuGroup(localized("Language")) {
                KukuRow(
                    localized("Interface language"),
                    caption: localized("Follows macOS by default. Changes take effect when SayKuku reopens.")
                ) {
                    KukuPicker(
                        localized("Interface language"),
                        options: AppLanguage.allCases,
                        selection: Binding(get: { appState.settings.appLanguage }, set: { changeLanguage(to: $0) }),
                        label: { $0.title }
                    )
                }
            }

            KukuGroup(localized("System permissions")) {
                PermissionActionRow(kind: .microphone)
                KukuDivider()
                PermissionActionRow(kind: .accessibility)
                KukuDivider()
                KukuRow(
                    localized("Permission guide"),
                    caption: localized("Recheck status, enable access, and test the microphone")
                ) {
                    Button(localized("Open Guide")) {
                        appState.showPermissionGuide()
                        appState.showMainWindow()
                    }
                    .buttonStyle(.kukuSecondary)
                }
            }

            KukuGroup(localized("Startup & background")) {
                KukuToggleRow(
                    title: localized("Open at login"),
                    caption: localized("Keep Fn gestures ready"),
                    isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.setLaunchAtLogin($0) }
                    )
                )
                KukuDivider()
                KukuToggleRow(
                    title: localized("Show in menu bar"),
                    caption: appState.settings.hideDockIconAfterMainWindowCloses
                        ? localized("Required while the Dock icon is hidden")
                        : localized("Start input, open the app, and check shortcut status"),
                    isOn: Binding(
                        get: { appState.settings.showInMenuBar },
                        set: { appState.settings.setShowInMenuBar($0) }
                    )
                )
                .disabled(appState.settings.hideDockIconAfterMainWindowCloses)
                KukuDivider()
                KukuToggleRow(
                    title: localized("Hide Dock icon when window is closed"),
                    caption: localized("SayKuku keeps running in the menu bar. Reopening the window brings the Dock icon back."),
                    isOn: $settings.hideDockIconAfterMainWindowCloses
                )
            }

            KukuGroup(localized("Overlay")) {
                KukuRow(
                    localized("Position"),
                    caption: localized("Where the Voice Input and Voice Agent overlay appears")
                ) {
                    KukuPicker(
                        localized("Overlay position"),
                        options: OverlayPlacement.allCases,
                        selection: $settings.overlayPlacement,
                        label: { $0.title }
                    )
                }
            }

            KukuGroup(localized("Shortcuts")) {
                GlobalShortcutSettings()
            }

            SoftwareUpdateSettings()
        }
    }

    /// macOS applies `AppleLanguages` only at launch, so offer to reopen now.
    private func changeLanguage(to language: AppLanguage) {
        guard language != appState.settings.appLanguage else { return }
        appState.settings.appLanguage = language
        // After the menu closes and SwiftUI finishes applying the selection.
        Task {
            let alert = NSAlert()
            alert.messageText = localized("Changes take effect when SayKuku reopens")
            alert.addButton(withTitle: localized("Reopen Now"))
            alert.addButton(withTitle: localized("Later"))
            if alert.runModal() == .alertFirstButtonReturn { appState.relaunch() }
        }
    }
}

/// Version and update checks. Dev builds have no checker, so only the version shows.
private struct SoftwareUpdateSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings

        KukuGroup(localized("Software Update")) {
            KukuRow(localized("Version"), caption: versionCaption) {
                if let checker = appState.updateChecker {
                    Button(localized("Check for Updates…")) {
                        Task { await checker.checkManually() }
                    }
                    .buttonStyle(.kukuSecondary)
                    .disabled(checker.isChecking)
                }
            }
            if appState.updateChecker != nil {
                KukuDivider()
                KukuToggleRow(
                    title: localized("Check for updates automatically"),
                    caption: localized("Checks at launch, then once a day"),
                    isOn: $settings.automaticUpdateChecks
                )
            }
        }
    }

    /// "1.0.0 (181)"; `swift run` has no Info.plist to read.
    private var versionCaption: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String,
              let build = info?["CFBundleVersion"] as? String else {
            return localized("Development build")
        }
        let caption = "\(version) (\(build))"
        guard appState.updateChecker == nil else { return caption }
        return caption + localized(" · Dev builds don’t check for updates")
    }
}

private struct GlobalShortcutSettings: View {
    @State private var recorder = ShortcutRecorder()

    var body: some View {
        VStack(spacing: 0) {
            ShortcutStatusRow()
            KukuDivider()
            GlobalShortcutRow(action: .voiceInput, recorder: recorder)
            KukuDivider()
            GlobalShortcutRow(action: .voiceAgent, recorder: recorder)
        }
        .onDisappear { recorder.stop() }
    }
}

private struct GlobalShortcutRow: View {
    @Environment(AppState.self) private var appState
    let action: GlobalShortcutAction
    let recorder: ShortcutRecorder

    var body: some View {
        let issue = recorder.action == action ? recorder.issue : nil

        HStack(spacing: KukuSpacing.md) {
            VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                Text(action.title)
                    .font(.kuku(.body))
                    .foregroundStyle(KukuColor.textPrimary)
                Group {
                    if let issue {
                        KukuStatusLabel(text: issue.message(for: action), tone: .warning)
                    } else {
                        Text(subtitle).foregroundStyle(KukuColor.textSecondary)
                    }
                }
                .font(.kuku(.subheadline))
            }
            Spacer(minLength: KukuSpacing.md)
            ShortcutRecorderButton(action: action, recorder: recorder)
        }
        .kukuRowFrame()
    }

    private var subtitle: String {
        let gesture = action.fnGesture
        if recorder.action == action {
            return localized("Press a modifier alone or a shortcut · Esc to cancel · Delete to turn off")
        }
        guard let shortcut = appState.settings.globalShortcut(for: action) else {
            return localized("Off. \(gesture) still works.")
        }
        if shortcut.modifierTapCount == 2 {
            return localized("Double-press to start or finish. \(gesture) still works.")
        }
        return localized("Press to start, press again to finish. \(gesture) still works.")
    }
}

private struct ShortcutStatusRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: KukuSpacing.md) {
            Image(systemName: appState.shortcutStatus.symbol)
                .font(.kukuIcon(.regular, weight: .semibold))
                .foregroundStyle((appState.shortcutStatus == .ready ? KukuStatusTone.success : .warning).iconColor)
                // Fixed icon column so the text doesn't shift when the symbol changes.
                .frame(width: 18)

            VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                Text(localized("Shortcut status"))
                    .font(.kuku(.body))
                    .foregroundStyle(KukuColor.textPrimary)
                Text(appState.shortcutStatus.title(appState))
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
                if let fnWarning {
                    KukuStatusLabel(text: fnWarning, tone: .warning)
                }
            }

            Spacer(minLength: KukuSpacing.md)

            if appState.shortcutStatus == .accessibilityRequired {
                Button(localized("Enable Accessibility")) {
                    Task { await appState.requestPermission(.accessibility) }
                }
                .buttonStyle(.kukuSecondary)
            } else {
                Button(localized("Keyboard Settings")) {
                    appState.openKeyboardSettings()
                }
                .buttonStyle(.kukuSecondary)
            }
        }
        .kukuRowFrame()
    }

    /// Shown only when the system Fn action competes with SayKuku's Fn gestures.
    private var fnWarning: String? {
        guard let usage = appState.systemPermissions.fnKeyUsage else { return nil }
        let doNothing = FnKeyUsage.doNothing.title
        switch usage {
        case .doNothing:
            return nil
        case .changeInputSource, .showEmoji:
            return localized("Fn is set to “\(usage.title)”. Set “Press fn key to” to “\(doNothing)” in Keyboard Settings.")
        case .startDictation:
            return localized(
                "Fn is set to “\(usage.title)”. Pressing Fn twice opens system Dictation; set it to “\(doNothing)” in Keyboard Settings."
            )
        }
    }
}

private struct HistorySettings: View {
    @Environment(AppState.self) private var appState
    @State private var isConfirmingClear = false

    var body: some View {
        @Bindable var settings = appState.settings

        SettingsStack(
            title: localized("History"),
            subtitle: localized("History and recordings stay on this Mac and are deleted on schedule.")
        ) {
            KukuGroup(localized("Storage")) {
                KukuRow(
                    localized("Keep history"),
                    caption: appState.settings.historyRetention == .off
                        ? localized("New items aren’t saved. Existing ones stay until you clear them.")
                        : localized("Starred items are never deleted automatically")
                ) {
                    KukuPicker(
                        localized("Keep history"),
                        options: HistoryRetention.allCases,
                        selection: $settings.historyRetention,
                        label: { $0.title }
                    )
                }

                KukuDivider()

                KukuToggleRow(
                    title: localized("Save recordings"),
                    caption: appState.settings.historyRetention == .off
                        ? localized("History isn’t being kept")
                        : localized("Keep recordings so you can replay or retry them. They’re deleted with their history items."),
                    isOn: $settings.storeVoiceAudio
                )
                .disabled(appState.settings.historyRetention == .off)
            }

            KukuGroup(localized("Manage")) {
                KukuRow(
                    localized("Clear all history"),
                    caption: localized("Remove every history item and recording from this Mac")
                ) {
                    Button(localized("Clear…")) { isConfirmingClear = true }
                        .buttonStyle(.kukuSecondary)
                        .disabled(appState.data.historyEntries.isEmpty)
                }
            }
        }
        .confirmationDialog(
            localized("Clear all history?"),
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(localized("Delete All"), role: .destructive) {
                appState.data.clearHistory(keepingStarred: false)
            }
            if starredCount > 0 {
                Button(localized("Delete All but Starred")) {
                    appState.data.clearHistory(keepingStarred: true)
                }
            }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(clearMessage)
        }
    }

    private var starredCount: Int {
        appState.data.historyEntries.filter(\.isStarred).count
    }

    private var clearMessage: String {
        let count = starredCount
        guard count > 0 else {
            return localized("All history and recordings will be removed from this Mac. This can’t be undone.")
        }
        return localized(
            "Delete All also removes \(count) starred items and every recording. This can’t be undone. To keep starred items, choose Delete All but Starred."
        )
    }
}

private struct SettingsStack<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: KukuLayout.sectionSpacing) {
            VStack(alignment: .leading, spacing: KukuSpacing.xs) {
                Text(title)
                    .font(.kuku(.title))
                    .foregroundStyle(KukuColor.textPrimary)
                Text(subtitle)
                    .font(.kuku(.callout))
                    .foregroundStyle(KukuColor.textSecondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsOptionRow<Option: CaseIterable & Hashable & Identifiable>: View
where Option.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        KukuRow(title) {
            KukuPicker(title, options: Array(Option.allCases), selection: $selection, label: label)
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, voiceInput, voiceAgent, history, privacy, qwen
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .voiceInput: "mic"
        case .voiceAgent: "sparkles"
        case .history: "clock.arrow.circlepath"
        case .privacy: "hand.raised"
        case .qwen: "network"
        }
    }
    var title: String {
        switch self {
        case .general: localized("General")
        case .voiceInput: localized("Voice Input")
        case .voiceAgent: localized("Voice Agent")
        case .history: localized("History")
        case .privacy: localized("Privacy")
        case .qwen: localized("Qwen Connection")
        }
    }
}
