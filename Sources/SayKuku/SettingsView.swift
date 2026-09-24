import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: appState.text("设置", "Settings"),
                title: appState.text("按你的习惯使用 SayKuku", "Make SayKuku work your way"),
                subtitle: appState.text(
                    "调整语音输入、语音 Agent、隐私和 Qwen 连接。",
                    "Adjust Voice Input, Voice Agent, privacy, and your connection to Qwen."
                )
            )

            KukuPageTabs(
                items: SettingsSection.allCases,
                selection: $selection,
                title: { $0.title(appState) }
            )

            Divider().opacity(0.55)

            ScrollView {
                KukuPageContent {
                    Group {
                        switch selection {
                        case .general: GeneralSettings()
                        case .voiceInput: VoiceInputSettings()
                        case .voiceAgent: VoiceAgentSettings()
                        case .history: HistorySettings()
                        case .privacy: PrivacySettings()
                        case .qwen: QwenSettings()
                        }
                    }
                }
                .padding(.vertical, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

private struct VoiceInputSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsStack(title: appState.voiceInputTitle, subtitle: appState.text("说什么就输入什么，不改你的意思。", "Types what you say, without changing what you mean.")) {
            SettingsGroup(title: appState.text("输入方式", "Input gesture")) {
                VStack(spacing: 0) {
                    ForEach(InputMode.allCases) { mode in
                        ChoiceRow(
                            title: mode == .hold ? appState.text("按住 Fn", "Hold Fn") : appState.text("单击 Fn", "Tap Fn"),
                            subtitle: mode == .hold
                                ? appState.text("按住片刻开始录音，松开即输入", "Hold briefly to start, release to insert")
                                : appState.text("单击开始录音，再次单击即输入", "Tap to start, tap again to insert"),
                            selected: appState.inputMode == mode
                        ) {
                            appState.inputMode = mode
                        }
                    }
                }
            }

            SettingsGroup(title: appState.text("麦克风测试", "Microphone test")) {
                MicrophoneTestPanel()
            }

            SettingsGroup(title: appState.text("结束与输出", "Stop & output")) {
                SettingsToggle(title: appState.text("停顿后自动结束", "Stop after a pause"), subtitle: appState.text("停顿约 1 秒后结束录音", "Ends recording after about 1 second of silence"), isOn: $appState.autoStop)
                SettingsDivider()
                SettingsOptionRow(
                    title: appState.text("识别语言", "Recognition language"),
                    selection: $appState.recognitionLanguage
                ) { language in
                    language.title(isChineseUI: appState.usesChineseUI)
                }
                SettingsDivider()
                SettingsOptionRow(
                    title: appState.text("数字格式", "Number format"),
                    selection: $appState.dictationNumberFormat
                ) { format in
                    format.title(isChineseUI: appState.usesChineseUI)
                }
                SettingsDivider()
                SettingsOptionRow(
                    title: appState.text("口语整理", "Speech cleanup"),
                    selection: $appState.dictationCleanup
                ) { cleanup in
                    cleanup.title(isChineseUI: appState.usesChineseUI)
                }
                Text(appState.text(
                    "轻整理会去掉无意义口癖和紧邻重复；原样保留说话时的停顿与重复。",
                    "Light cleanup removes fillers and accidental repeats. Verbatim keeps hesitations and repeats."
                ))
                .font(.system(size: 10.5))
                .foregroundStyle(KukuColor.stone)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            SettingsGroup(title: appState.text("词汇", "Vocabulary")) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.text("常用领域与词汇", "Domains & Vocabulary"))
                            .font(.system(size: 12.5, weight: .medium))
                        Text(domainSummary)
                            .font(.system(size: 10.5))
                            .foregroundStyle(KukuColor.stone)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 16)
                    Button(appState.text("编辑…", "Edit…")) {
                        appState.showDomainOnboarding()
                    }
                    .buttonStyle(TintButtonStyle())
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            }
        }
    }

    private var domainSummary: String {
        let domains = DomainPreset.allCases
            .filter(appState.selectedDomains.contains)
            .map { $0.title(isChineseUI: appState.usesChineseUI) }
        let values = domains + appState.customDomainTerms
        return values.isEmpty
            ? appState.text("尚未选择，可添加 Vibe Coding 等常用词", "None yet. Add terms like Vibe Coding.")
            : values.joined(separator: appState.text("、", ", "))
    }
}

private struct VoiceAgentSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsStack(title: appState.voiceAgentTitle, subtitle: appState.text("连按两次 Fn，说出要写、修改或查询的内容。", "Press Fn twice to write, edit, or ask by voice.")) {
            SettingsGroup(title: appState.text("交互", "Interaction")) {
                SettingsToggle(
                    title: appState.text("连续对话", "Continuous conversation"),
                    subtitle: appState.text(
                        "记住同一个 App 中最近的对话，30 分钟后自动清除，可在“记忆 › 短期”中查看",
                        "Remembers recent conversations in the same app for 30 minutes. See Memory › Short-Term."
                    ),
                    isOn: $appState.continuousConversation
                )
                SettingsDivider()
                SettingsToggle(
                    title: appState.text("自动写入", "Insert automatically"),
                    subtitle: appState.text(
                        "把结果直接写入你正在用的输入框；关闭后结果留在浮层，供你复制",
                        "Puts results right into the text field you’re using. When off, they stay in the overlay for you to copy."
                    ),
                    isOn: $appState.automaticAgentWriteBack
                )
            }
        }
    }
}

private struct PrivacySettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsStack(title: appState.text("语音 Agent 可使用的内容", "What Voice Agent can use"), subtitle: appState.text("说话时，可在浮层中查看本次会发送的内容。", "While you talk, the overlay shows what’s sent.")) {
            SettingsGroup(title: appState.text("允许使用", "Allow access to")) {
                SettingsToggle(title: appState.text("选中文字", "Selected text"), subtitle: appState.text("用于改写选中的文字，或针对它提问", "Used to rewrite or ask about the text you’ve selected"), isOn: $appState.selectedTextAllowed)
                SettingsDivider()
                SettingsToggle(title: appState.text("当前 App", "Current app"), subtitle: appState.text("你正在使用的 App 名称", "Name of the app you’re using"), isOn: $appState.currentAppAllowed)
                SettingsDivider()
                SettingsToggle(title: appState.text("窗口标题", "Window title"), subtitle: appState.text("包括无痕窗口", "Includes private windows"), isOn: $appState.windowTitleAllowed)
                SettingsDivider()
                SettingsToggle(title: appState.text("剪贴板", "Clipboard"), subtitle: appState.text("剪贴板中的文字，密码类内容除外", "Text on your clipboard, excluding passwords"), isOn: $appState.clipboardAllowed)
                SettingsDivider()
                SettingsToggle(title: appState.text("浏览器页面", "Browser page"), subtitle: appState.text("Safari 或 Chrome 当前页面的网址", "URL of the current Safari or Chrome page"), isOn: $appState.browserPageAllowed)
            }
            SettingsGroup(title: appState.text("始终不读取或写入", "Always off-limits")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        PrivacyApp(name: appState.text("密码框", "Password fields"), symbol: "lock.fill")
                        PrivacyApp(name: appState.text("密码管理器", "Password managers"), symbol: "key.fill")
                    }
                    Text(appState.text(
                        "密码管理器包括 1Password、Bitwarden、LastPass、Dashlane、KeePassXC、钥匙串访问和“密码”。",
                        "Password managers include 1Password, Bitwarden, LastPass, Dashlane, KeePassXC, Keychain Access, and Passwords."
                    ))
                    .font(.system(size: 10.5))
                    .foregroundStyle(KukuColor.stone)
                }
                .padding(14)
            }
        }
    }
}

private struct QwenSettings: View {
    @Environment(AppState.self) private var appState
    @State private var apiKeyDraft = ""

    var body: some View {
        @Bindable var appState = appState
        SettingsStack(title: appState.text("Qwen 连接", "Qwen Connection"), subtitle: appState.text("连接 Qwen，并选择语音输入和语音 Agent 使用的模型。", "Connect Qwen and choose models for Voice Input and Voice Agent.")) {
            SettingsGroup(title: appState.text("连接", "Connection")) {
                QwenConnectionForm(apiKeyDraft: $apiKeyDraft)
            }
            SettingsGroup(title: appState.text("模型", "Models")) {
                ModelPickerRow(
                    title: appState.voiceInputTitle,
                    caption: appState.text("实时识别语音", "Real-time transcription"),
                    value: $appState.realtimeModel,
                    presets: QwenModelCatalog.realtimeModels
                )
                SettingsDivider()
                ModelPickerRow(
                    title: appState.voiceAgentTitle,
                    caption: appState.text("也用于整理知识和重新识别录音", "Also used to organize Knowledge and retry recordings"),
                    value: $appState.reasoningModel,
                    presets: QwenModelCatalog.reasoningModels
                )
            }
            HStack {
                QwenConnectionStatus()
                Spacer()
                QwenTestButton(apiKeyDraft: apiKeyDraft)
            }
        }
    }
}

/// Region, API Key, and workspace rows shared by Settings and the first-run setup sheet.
struct QwenConnectionForm: View {
    @Environment(AppState.self) private var appState
    @Binding var apiKeyDraft: String
    /// First-run setup hides it so Save & Test is the only way to save.
    var showsSaveButton = true

    var body: some View {
        @Bindable var appState = appState
        let keyState = APIKeyDraftState(draft: apiKeyDraft, saved: appState.apiKey)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SettingsRowLabel(
                    title: appState.text("地域", "Region"),
                    caption: appState.text("需与 API Key 所属地域一致", "Must match where your API Key was created")
                )
                Spacer()
                Picker(appState.text("地域", "Region"), selection: $appState.qwenRegion) {
                    ForEach(QwenRegion.allCases) { region in
                        Text(region.title(isChineseUI: appState.usesChineseUI)).tag(region)
                    }
                }
                .labelsHidden()
                .frame(width: SettingsMetrics.pickerWidth)
            }
            .padding(14)
            SettingsDivider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("API Key").font(.system(size: 12.5, weight: .medium))
                    keyCaption(keyState)
                        .font(.system(size: 10.5))
                    Link(destination: apiKeyHelpURL) {
                        Label(appState.text("获取 API Key", "Get an API Key"), systemImage: "arrow.up.right.square")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KukuColor.coral)
                }
                Spacer()
                SecureField("sk-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit(saveKey)
                    .accessibilityLabel("API Key")
                if showsSaveButton {
                    Button(appState.text("保存", "Save"), action: saveKey)
                        .buttonStyle(HoverFillButtonStyle())
                        .disabled(!keyState.hasChanges)
                }
            }
            .padding(14)
            SettingsDivider()
            HStack {
                SettingsRowLabel(
                    title: appState.text("业务空间 ID", "Workspace ID"),
                    caption: appState.text(
                        "可选，仅在阿里云百炼中使用了业务空间时填写",
                        "Optional. Only needed if you use a workspace in Alibaba Cloud Model Studio."
                    )
                )
                Spacer()
                TextField("ws-…", text: $appState.qwenWorkspaceID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsMetrics.pickerWidth)
                    .accessibilityLabel(appState.text("业务空间 ID", "Workspace ID"))
            }
            .padding(14)
        }
        .onChange(of: appState.apiKey, initial: true) { _, saved in apiKeyDraft = saved }
    }

    @ViewBuilder
    private func keyCaption(_ state: APIKeyDraftState) -> some View {
        switch state {
        case .empty:
            Text(appState.text("保存在这台 Mac 的钥匙串中", "Stored in this Mac’s Keychain"))
                .foregroundStyle(KukuColor.stone)
        case .saved:
            StatusLabel(text: appState.text("已保存到钥匙串", "Saved to Keychain"), symbol: "checkmark.circle.fill", tint: KukuColor.mint)
        case .modified:
            StatusLabel(text: appState.text("尚未保存", "Not saved yet"), symbol: "exclamationmark.circle.fill", tint: KukuColor.amber)
        case .cleared:
            StatusLabel(text: appState.text("保存后将移除", "Will be removed when you save"), symbol: "exclamationmark.circle.fill", tint: KukuColor.amber)
        }
    }

    private var apiKeyHelpURL: URL {
        URL(string: appState.usesChineseUI
            ? "https://help.aliyun.com/zh/model-studio/get-api-key"
            : "https://www.alibabacloud.com/help/en/model-studio/get-api-key")!
    }

    private func saveKey() {
        guard APIKeyDraftState(draft: apiKeyDraft, saved: appState.apiKey).hasChanges else { return }
        do {
            try appState.saveAPIKey(apiKeyDraft)
        } catch {
            appState.connectionState = .failed(appState.localizedError(error))
        }
    }
}

struct QwenConnectionStatus: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.connectionState {
        case .connected(let realtime, let chat):
            StatusLabel(
                text: appState.text(
                    "连接正常 · 语音输入 \(realtime) ms · 语音 Agent \(chat) ms",
                    "Connected · Voice Input \(realtime) ms · Voice Agent \(chat) ms"
                ),
                symbol: "checkmark.circle.fill",
                tint: KukuColor.mint
            )
            .font(.system(size: 11, weight: .semibold))
        case .failed(let message):
            StatusLabel(text: message, symbol: "exclamationmark.triangle.fill", tint: KukuColor.amber)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
        case .idle, .testing:
            EmptyView()
        }
    }
}

struct QwenTestButton: View {
    @Environment(AppState.self) private var appState
    let apiKeyDraft: String

    var body: some View {
        let isTesting = appState.connectionState == .testing
        Button(isTesting ? appState.text("正在测试…", "Testing…") : appState.text("保存并测试", "Save & Test")) {
            Task { await appState.testQwenConnection(apiKey: apiKeyDraft) }
        }
        .buttonStyle(HoverFillButtonStyle(prominent: true))
        .disabled(isTesting || apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private struct ModelPickerRow: View {
    private enum Choice: Hashable { case model(String), custom }

    @Environment(AppState.self) private var appState
    let title: String
    let caption: String
    @Binding var value: String
    let presets: [String]
    @State private var customDraft: String?

    var body: some View {
        HStack {
            SettingsRowLabel(title: title, caption: caption)
            Spacer()
            if let draft = customDraft {
                TextField(
                    appState.text("模型 ID", "Model ID"),
                    text: Binding(get: { draft }, set: { customDraft = $0 })
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
                .onSubmit(applyCustomModel)
                .onExitCommand { customDraft = nil }
                Button(appState.text("使用", "Use"), action: applyCustomModel)
                    .buttonStyle(HoverFillButtonStyle())
            } else {
                Picker(title, selection: selection) {
                    ForEach(QwenModelCatalog.options(presets, including: value), id: \.self) { model in
                        Text(model).tag(Choice.model(model))
                    }
                    Divider()
                    Text(appState.text("自定义…", "Custom…")).tag(Choice.custom)
                }
                .labelsHidden()
                .frame(width: SettingsMetrics.pickerWidth)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }

    private var selection: Binding<Choice> {
        Binding(
            get: { .model(value) },
            set: { choice in
                switch choice {
                case .model(let model): value = model
                case .custom: customDraft = value
                }
            }
        )
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
        @Bindable var appState = appState

        SettingsStack(title: appState.text("通用", "General"), subtitle: appState.text("语言、权限、启动方式和快捷键。", "Language, permissions, startup, and shortcuts.")) {
            SettingsGroup(title: appState.text("语言", "Language")) {
                HStack {
                    SettingsRowLabel(
                        title: appState.text("界面语言", "Interface language"),
                        caption: appState.text("默认跟随 macOS，可随时切换", "Follows macOS by default. Change it anytime.")
                    )
                    Spacer()
                    Picker(appState.text("界面语言", "Interface language"), selection: $appState.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title(isChineseUI: appState.usesChineseUI)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsMetrics.pickerWidth)
                }
                .padding(14)
            }

            SettingsGroup(title: appState.text("系统权限", "System permissions")) {
                PermissionActionRow(kind: .microphone)
                SettingsDivider()
                PermissionActionRow(kind: .accessibility)
                SettingsDivider()
                HStack(spacing: 12) {
                    SettingsRowLabel(
                        title: appState.text("权限引导", "Permission guide"),
                        caption: appState.text("重新检查状态、开启权限并测试麦克风", "Recheck status, enable access, and test the microphone")
                    )
                    Spacer()
                    Button(appState.text("打开引导", "Open Guide")) {
                        appState.showPermissionGuide()
                    }
                    .buttonStyle(TintButtonStyle())
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            }

            SettingsGroup(title: appState.text("启动与后台", "Startup & background")) {
                SettingsToggle(
                    title: appState.text("登录时打开", "Open at login"),
                    subtitle: appState.text("确保 Fn 手势随时可用", "Keep Fn gestures ready"),
                    isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.setLaunchAtLogin($0) }
                    )
                )
                SettingsDivider()
                SettingsToggle(
                    title: appState.text("在菜单栏显示", "Show in menu bar"),
                    subtitle: appState.hideDockIconAfterMainWindowCloses
                        ? appState.text("开启“关闭窗口后隐藏 Dock 图标”时需保留", "Required while the Dock icon is hidden")
                        : appState.text("快速开始输入、打开窗口并查看快捷键状态", "Start input, open the app, and check shortcut status"),
                    isOn: Binding(
                        get: { appState.showInMenuBar },
                        set: { appState.setShowInMenuBar($0) }
                    )
                )
                .disabled(appState.hideDockIconAfterMainWindowCloses)
                SettingsDivider()
                SettingsToggle(
                    title: appState.text("关闭窗口后隐藏 Dock 图标", "Hide Dock icon when window is closed"),
                    subtitle: appState.text(
                        "SayKuku 仍在菜单栏运行，重新打开窗口时 Dock 图标会恢复",
                        "SayKuku keeps running in the menu bar. Reopening the window brings the Dock icon back."
                    ),
                    isOn: $appState.hideDockIconAfterMainWindowCloses
                )
            }

            SettingsGroup(title: appState.text("快捷键", "Shortcuts")) {
                GlobalShortcutSettings()
            }
        }
    }
}

private struct GlobalShortcutSettings: View {
    @State private var recorder = ShortcutRecorder()

    var body: some View {
        VStack(spacing: 0) {
            ShortcutStatusRow()
            SettingsDivider()
            GlobalShortcutRow(action: .voiceInput, recorder: recorder)
            SettingsDivider()
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

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title(appState))
                    .font(.system(size: 12.5, weight: .medium))
                Group {
                    if let issue {
                        StatusLabel(text: issue.message(for: action, appState), symbol: "exclamationmark.triangle.fill", tint: KukuColor.amber)
                    } else {
                        Text(subtitle).foregroundStyle(KukuColor.stone)
                    }
                }
                .font(.system(size: 10.5))
            }
            Spacer(minLength: 12)
            ShortcutRecorderButton(action: action, recorder: recorder)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }

    private var subtitle: String {
        let gesture = action.fnGesture(appState)
        if recorder.action == action {
            return appState.text("按下新的组合键 · Esc 取消 · Delete 关闭", "Press new keys · Esc to cancel · Delete to turn off")
        }
        if appState.globalShortcut(for: action) == nil {
            return appState.text("已关闭，\(gesture) 照常可用", "Off. \(gesture) still works.")
        }
        return appState.text("按一次开始，再按一次结束；\(gesture) 照常可用", "Press to start, press again to finish. \(gesture) still works.")
    }
}

private struct ShortcutStatusRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: appState.shortcutStatus.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(appState.shortcutStatus == .ready ? KukuColor.mint : KukuColor.amber)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(appState.text("快捷键状态", "Shortcut status"))
                    .font(.system(size: 12.5, weight: .medium))
                Text(appState.shortcutStatus.title(appState))
                    .font(.system(size: 10.5))
                    .foregroundStyle(KukuColor.stone)
                Group {
                    Text(appState.text(
                        "若按 Fn 会切换输入法，请在键盘设置中将“按下 fn 键时”设为“不执行任何操作”。",
                        "If Fn switches input sources, set “Press fn key to” to “Do Nothing” in Keyboard Settings."
                    ))
                    Text(appState.text(
                        "若连按两次 Fn 会打开系统听写，请更改听写的快捷键。",
                        "If pressing Fn twice starts Dictation, change the Dictation shortcut."
                    ))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(KukuColor.stone)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if appState.shortcutStatus == .accessibilityRequired {
                Button(appState.text("启用 Fn", "Enable Fn")) {
                    Task { await appState.requestPermission(.accessibility) }
                }
                .buttonStyle(TintButtonStyle())
            } else {
                Button(appState.text("键盘设置", "Keyboard Settings")) {
                    appState.openKeyboardSettings()
                }
                .buttonStyle(HoverFillButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }
}

private struct HistorySettings: View {
    @Environment(AppState.self) private var appState
    @State private var isConfirmingClear = false

    var body: some View {
        @Bindable var appState = appState

        SettingsStack(
            title: appState.text("历史", "History"),
            subtitle: appState.text(
                "历史记录和录音只保存在这台 Mac 上，并按期限自动删除。",
                "History and recordings stay on this Mac and are deleted on schedule."
            )
        ) {
            SettingsGroup(title: appState.text("存储", "Storage")) {
                HStack {
                    SettingsRowLabel(
                        title: appState.text("自动删除", "Delete history after"),
                        caption: appState.text("星标记录不受此期限影响", "Starred items are never deleted automatically")
                    )
                    Spacer()
                    Picker(appState.text("自动删除", "Delete history after"), selection: $appState.historyRetention) {
                        ForEach(HistoryRetention.allCases) { retention in
                            Text(retention.title(appState)).tag(retention)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsMetrics.pickerWidth)
                }
                .padding(14)

                SettingsDivider()

                SettingsToggle(
                    title: appState.text("保存录音", "Save recordings"),
                    subtitle: appState.text(
                        "保留录音，方便回放和重新识别，并随对应的历史记录一起删除",
                        "Keep recordings so you can replay or retry them. They’re deleted with their history items."
                    ),
                    isOn: $appState.storeVoiceAudio
                )
            }

            SettingsGroup(title: appState.text("管理", "Manage")) {
                HStack {
                    SettingsRowLabel(
                        title: appState.text("清空全部历史", "Clear all history"),
                        caption: appState.text("删除这台 Mac 上的所有历史记录和录音", "Remove every history item and recording from this Mac")
                    )
                    Spacer()
                    Button(appState.text("清空…", "Clear…")) { isConfirmingClear = true }
                        .buttonStyle(HoverFillButtonStyle())
                        .disabled(appState.historyEntries.isEmpty)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            }
        }
        .confirmationDialog(
            appState.text("清空全部历史？", "Clear all history?"),
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(appState.text("全部删除", "Delete All"), role: .destructive) {
                appState.clearHistory(keepingStarred: false)
            }
            if starredCount > 0 {
                Button(appState.text("保留星标，删除其余", "Delete All but Starred")) {
                    appState.clearHistory(keepingStarred: true)
                }
            }
            Button(appState.text("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(clearMessage)
        }
    }

    private var starredCount: Int {
        appState.historyEntries.filter(\.isStarred).count
    }

    private var clearMessage: String {
        let count = starredCount
        guard count > 0 else {
            return appState.text(
                "所有历史记录和录音都会从这台 Mac 上删除，且无法恢复。",
                "All history and recordings will be removed from this Mac. This can’t be undone."
            )
        }
        let starredItems = count == 1 ? "1 starred item" : "\(count) starred items"
        return appState.text(
            "“全部删除”会连同 \(count) 条星标记录和所有录音一起删除，且无法恢复。想保留星标记录，请选“保留星标，删除其余”。",
            "Delete All also removes \(starredItems) and every recording. This can’t be undone. To keep starred items, choose Delete All but Starred."
        )
    }
}

private struct SettingsStack<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(KukuColor.stone)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(KukuColor.stone)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .kukuSurface(radius: KukuLayout.radiusMedium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum SettingsMetrics {
    static let pickerWidth: CGFloat = 220
}

/// Row title with its caption, in the sizes every settings row shares.
private struct SettingsRowLabel: View {
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12.5, weight: .medium))
            Text(caption).font(.system(size: 10.5)).foregroundStyle(KukuColor.stone)
        }
    }
}

/// Ink text with a tinted icon; mint and amber are too light for small text.
private struct StatusLabel: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(text).foregroundStyle(KukuColor.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }
}

private struct SettingsToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            SettingsRowLabel(title: title, caption: subtitle)
            Spacer()
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }
}

private struct SettingsOptionRow<Option: CaseIterable & Hashable & Identifiable>: View
where Option.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12.5, weight: .medium))
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(Option.allCases) { option in
                    Text(label(option)).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: SettingsMetrics.pickerWidth)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    }
}

private struct SettingsDivider: View {
    var body: some View { Divider().padding(.leading, 14).opacity(0.5) }
}

private struct ChoiceRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? KukuColor.coral : KukuColor.stone)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(KukuColor.stone)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? KukuColor.coralSoft.opacity(0.34) : .clear, in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PrivacyApp: View {
    let name: String
    let symbol: String
    var body: some View {
        Label(name, systemImage: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(KukuColor.stone)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(KukuColor.shade.opacity(0.045), in: Capsule())
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, voiceInput, voiceAgent, history, privacy, qwen
    var id: String { rawValue }
    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .general: appState.text("通用", "General")
        case .voiceInput: appState.voiceInputTitle
        case .voiceAgent: appState.voiceAgentTitle
        case .history: appState.text("历史", "History")
        case .privacy: appState.text("隐私", "Privacy")
        case .qwen: appState.text("Qwen 连接", "Qwen Connection")
        }
    }
    var symbol: String {
        switch self {
        case .general: "switch.2"
        case .voiceInput: "mic"
        case .voiceAgent: "sparkles"
        case .history: "clock.arrow.circlepath"
        case .privacy: "hand.raised"
        case .qwen: "bolt.horizontal.circle"
        }
    }
}
