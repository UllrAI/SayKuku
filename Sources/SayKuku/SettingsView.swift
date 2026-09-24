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

            KukuDivider(inset: 0)

            KukuPageScroll {
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
    }
}

private struct VoiceInputSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsStack(title: appState.voiceInputTitle, subtitle: appState.text("说什么就输入什么，不改你的意思。", "Types what you say, without changing what you mean.")) {
            KukuGroup(appState.text("输入方式", "Input gesture")) {
                ForEach(InputMode.allCases) { mode in
                    if mode != InputMode.allCases.first {
                        KukuDivider()
                    }
                    KukuChoiceRow(
                        title: mode == .hold ? appState.text("按住 Fn", "Hold Fn") : appState.text("单击 Fn", "Tap Fn"),
                        caption: mode == .hold
                            ? appState.text("按住片刻开始录音，松开即输入", "Hold briefly to start, release to insert")
                            : appState.text("单击开始录音，再次单击即输入", "Tap to start, tap again to insert"),
                        isSelected: appState.inputMode == mode
                    ) {
                        appState.inputMode = mode
                    }
                }
            }

            KukuGroup(appState.text("麦克风测试", "Microphone test")) {
                MicrophoneTestPanel()
            }

            KukuGroup(appState.text("结束与输出", "Stop & output")) {
                KukuToggleRow(title: appState.text("停顿后自动结束", "Stop after a pause"), caption: autoStopSubtitle, isOn: $appState.autoStop)
                KukuDivider()
                SettingsOptionRow(
                    title: appState.text("识别语言", "Recognition language"),
                    selection: $appState.recognitionLanguage
                ) { language in
                    language.title(isChineseUI: appState.usesChineseUI)
                }
                KukuDivider()
                SettingsOptionRow(
                    title: appState.text("数字格式", "Number format"),
                    selection: $appState.dictationNumberFormat
                ) { format in
                    format.title(isChineseUI: appState.usesChineseUI)
                }
                KukuDivider()
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
                .font(.kuku(.subheadline))
                .foregroundStyle(KukuColor.textSecondary)
                .padding(.horizontal, KukuLayout.rowPadding)
                .padding(.bottom, KukuSpacing.md)
            }

            KukuGroup(appState.text("词汇", "Vocabulary")) {
                KukuRow(appState.text("常用领域与词汇", "Domains & Vocabulary"), caption: domainSummary) {
                    Button(appState.text("编辑…", "Edit…")) {
                        appState.showDomainOnboarding()
                    }
                    .buttonStyle(.kukuSecondary)
                }
                // Long custom vocabularies would otherwise stretch the row.
                .lineLimit(2)
            }
        }
    }

    /// Pause detection runs on the realtime session, which needs a workspace ID.
    private var autoStopSubtitle: String {
        appState.configuration.realtimeURL == nil
            ? appState.text("需先在“Qwen 连接”中填写业务空间 ID", "Requires a Workspace ID in Qwen Connection")
            : appState.text("停顿约 1 秒后结束录音", "Ends recording after about 1 second of silence")
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
            KukuGroup(appState.text("交互", "Interaction")) {
                KukuToggleRow(
                    title: appState.text("连续对话", "Continuous conversation"),
                    caption: appState.text(
                        "记住同一个 App 中最近的对话，30 分钟后自动清除，可在“记忆 › 短期”中查看",
                        "Remembers recent conversations in the same app for 30 minutes. See Memory › Short-Term."
                    ),
                    isOn: $appState.continuousConversation
                )
                KukuDivider()
                KukuToggleRow(
                    title: appState.text("自动写入", "Insert automatically"),
                    caption: appState.text(
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
            KukuGroup(appState.text("允许使用", "Allow access to")) {
                KukuToggleRow(title: appState.text("选中文字", "Selected text"), caption: appState.text("用于改写选中的文字，或针对它提问", "Used to rewrite or ask about the text you’ve selected"), isOn: $appState.selectedTextAllowed)
                KukuDivider()
                KukuToggleRow(title: appState.text("当前 App", "Current app"), caption: appState.text("你正在使用的 App 名称", "Name of the app you’re using"), isOn: $appState.currentAppAllowed)
                KukuDivider()
                KukuToggleRow(title: appState.text("窗口标题", "Window title"), caption: appState.text("包括无痕窗口", "Includes private windows"), isOn: $appState.windowTitleAllowed)
                KukuDivider()
                KukuToggleRow(title: appState.text("剪贴板", "Clipboard"), caption: appState.text("剪贴板中的文字，密码类内容除外", "Text on your clipboard, excluding passwords"), isOn: $appState.clipboardAllowed)
                KukuDivider()
                KukuToggleRow(title: appState.text("浏览器页面", "Browser page"), caption: appState.text("Safari 或 Chrome 当前页面的网址", "URL of the current Safari or Chrome page"), isOn: $appState.browserPageAllowed)
            }
            KukuGroup(appState.text("始终不读取或写入", "Always off-limits")) {
                VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                    HStack(spacing: KukuSpacing.sm) {
                        KukuBadge(text: appState.text("密码框", "Password fields"), symbol: "lock.fill")
                        KukuBadge(text: appState.text("密码管理器", "Password managers"), symbol: "key.fill")
                    }
                    Text(appState.text(
                        "密码管理器包括 1Password、Bitwarden、LastPass、Dashlane、KeePassXC、钥匙串访问和“密码”。",
                        "Password managers include 1Password, Bitwarden, LastPass, Dashlane, KeePassXC, Keychain Access, and Passwords."
                    ))
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
                }
                .padding(KukuLayout.rowPadding)
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
            KukuGroup(appState.text("连接", "Connection")) {
                QwenConnectionForm(apiKeyDraft: $apiKeyDraft)
            }
            KukuGroup(appState.text("模型", "Models")) {
                ModelPickerRow(
                    title: appState.voiceInputTitle,
                    caption: appState.text("实时识别语音", "Real-time transcription"),
                    value: $appState.realtimeModel,
                    presets: QwenModelCatalog.realtimeModels
                )
                KukuDivider()
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
            HStack(spacing: KukuSpacing.md) {
                KukuRowLabel(
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
                .frame(width: KukuLayout.pickerWidth)
            }
            .kukuRowFrame()
            KukuDivider()
            HStack(spacing: KukuSpacing.md) {
                VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                    Text("API Key").font(.kuku(.body)).foregroundStyle(KukuColor.textPrimary)
                    keyCaption(keyState)
                        .font(.kuku(.subheadline))
                    helpLink(appState.text("获取 API Key", "Get an API Key"), page: "get-api-key")
                }
                Spacer()
                SecureField("sk-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    // Narrower than a picker so the Save button fits beside it.
                    .frame(width: 160)
                    .onSubmit(saveKey)
                    .accessibilityLabel("API Key")
                if showsSaveButton {
                    Button(appState.text("保存", "Save"), action: saveKey)
                        .buttonStyle(.kukuSecondary)
                        .disabled(!keyState.hasChanges)
                }
            }
            .kukuRowFrame()
            KukuDivider()
            HStack(spacing: KukuSpacing.md) {
                VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                    KukuRowLabel(
                        title: appState.text("业务空间 ID", "Workspace ID"),
                        caption: appState.text(
                            "可选，填写后语音输入会边说边识别，不用等你说完",
                            "Optional. Lets Voice Input transcribe as you speak instead of after you stop."
                        )
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    helpLink(appState.text("查看业务空间 ID", "Find Your Workspace ID"), page: "obtain-the-app-id-and-workspace-id")
                }
                Spacer()
                TextField("ws-…", text: $appState.qwenWorkspaceID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: KukuLayout.pickerWidth)
                    .accessibilityLabel(appState.text("业务空间 ID", "Workspace ID"))
            }
            .kukuRowFrame()
        }
        .onChange(of: appState.apiKey, initial: true) { _, saved in apiKeyDraft = saved }
    }

    @ViewBuilder
    private func keyCaption(_ state: APIKeyDraftState) -> some View {
        switch state {
        case .empty:
            Text(appState.text("保存在这台 Mac 的钥匙串中", "Stored in this Mac’s Keychain"))
                .foregroundStyle(KukuColor.textSecondary)
        case .saved:
            KukuStatusLabel(text: appState.text("已保存到钥匙串", "Saved to Keychain"), tone: .success)
        case .modified:
            KukuStatusLabel(text: appState.text("尚未保存", "Not saved yet"), tone: .warning)
        case .cleared:
            KukuStatusLabel(text: appState.text("保存后将移除", "Will be removed when you save"), tone: .warning)
        }
    }

    private func helpLink(_ title: String, page: String) -> some View {
        Link(destination: URL(string: appState.usesChineseUI
            ? "https://help.aliyun.com/zh/model-studio/\(page)"
            : "https://www.alibabacloud.com/help/en/model-studio/\(page)")!
        ) {
            Label(title, systemImage: "arrow.up.right.square")
        }
        .font(.kuku(.subheadline, weight: .medium))
        .foregroundStyle(KukuColor.accentText)
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
            KukuStatusLabel(
                text: connectedMessage(realtime: realtime, chat: chat),
                tone: .success,
                font: .kuku(.subheadline, weight: .medium)
            )
            .lineLimit(2)
        case .failed(let message):
            KukuStatusLabel(text: message, tone: .danger, font: .kuku(.subheadline, weight: .medium))
                .lineLimit(2)
        case .idle, .testing:
            EmptyView()
        }
    }

    private func connectedMessage(realtime: Int?, chat: Int) -> String {
        guard let realtime else {
            return appState.text(
                "连接正常 · 语音 Agent \(chat) ms · 未填写业务空间 ID，语音输入会在说完后识别",
                "Connected · Voice Agent \(chat) ms · Without a Workspace ID, Voice Input transcribes after you stop"
            )
        }
        return appState.text(
            "连接正常 · 语音输入 \(realtime) ms · 语音 Agent \(chat) ms",
            "Connected · Voice Input \(realtime) ms · Voice Agent \(chat) ms"
        )
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
        .buttonStyle(.kukuPrimary)
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
        KukuRow(title, caption: caption) {
            if let draft = customDraft {
                TextField(
                    appState.text("模型 ID", "Model ID"),
                    text: Binding(get: { draft }, set: { customDraft = $0 })
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: KukuLayout.pickerWidth)
                .onSubmit(applyCustomModel)
                .onExitCommand { customDraft = nil }
                Button(appState.text("使用", "Use"), action: applyCustomModel)
                    .buttonStyle(.kukuSecondary)
            } else {
                Picker(title, selection: selection) {
                    ForEach(QwenModelCatalog.options(presets, including: value), id: \.self) { model in
                        Text(model).tag(Choice.model(model))
                    }
                    Divider()
                    Text(appState.text("自定义…", "Custom…")).tag(Choice.custom)
                }
                .labelsHidden()
                .frame(width: KukuLayout.pickerWidth)
            }
        }
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
            KukuGroup(appState.text("语言", "Language")) {
                KukuRow(
                    appState.text("界面语言", "Interface language"),
                    caption: appState.text("默认跟随 macOS，可随时切换", "Follows macOS by default. Change it anytime.")
                ) {
                    Picker(appState.text("界面语言", "Interface language"), selection: $appState.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title(isChineseUI: appState.usesChineseUI)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: KukuLayout.pickerWidth)
                }
            }

            KukuGroup(appState.text("系统权限", "System permissions")) {
                PermissionActionRow(kind: .microphone)
                KukuDivider()
                PermissionActionRow(kind: .accessibility)
                KukuDivider()
                KukuRow(
                    appState.text("权限引导", "Permission guide"),
                    caption: appState.text("重新检查状态、开启权限并测试麦克风", "Recheck status, enable access, and test the microphone")
                ) {
                    Button(appState.text("打开引导", "Open Guide")) {
                        appState.showPermissionGuide()
                    }
                    .buttonStyle(.kukuSecondary)
                }
            }

            KukuGroup(appState.text("启动与后台", "Startup & background")) {
                KukuToggleRow(
                    title: appState.text("登录时打开", "Open at login"),
                    caption: appState.text("确保 Fn 手势随时可用", "Keep Fn gestures ready"),
                    isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.setLaunchAtLogin($0) }
                    )
                )
                KukuDivider()
                KukuToggleRow(
                    title: appState.text("在菜单栏显示", "Show in menu bar"),
                    caption: appState.hideDockIconAfterMainWindowCloses
                        ? appState.text("开启“关闭窗口后隐藏 Dock 图标”时需保留", "Required while the Dock icon is hidden")
                        : appState.text("快速开始输入、打开窗口并查看快捷键状态", "Start input, open the app, and check shortcut status"),
                    isOn: Binding(
                        get: { appState.showInMenuBar },
                        set: { appState.setShowInMenuBar($0) }
                    )
                )
                .disabled(appState.hideDockIconAfterMainWindowCloses)
                KukuDivider()
                KukuToggleRow(
                    title: appState.text("关闭窗口后隐藏 Dock 图标", "Hide Dock icon when window is closed"),
                    caption: appState.text(
                        "SayKuku 仍在菜单栏运行，重新打开窗口时 Dock 图标会恢复",
                        "SayKuku keeps running in the menu bar. Reopening the window brings the Dock icon back."
                    ),
                    isOn: $appState.hideDockIconAfterMainWindowCloses
                )
            }

            KukuGroup(appState.text("快捷键", "Shortcuts")) {
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
                Text(action.title(appState))
                    .font(.kuku(.body))
                    .foregroundStyle(KukuColor.textPrimary)
                Group {
                    if let issue {
                        KukuStatusLabel(text: issue.message(for: action, appState), tone: .warning)
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
        HStack(spacing: KukuSpacing.md) {
            Image(systemName: appState.shortcutStatus.symbol)
                .font(.kukuIcon(.regular, weight: .semibold))
                .foregroundStyle((appState.shortcutStatus == .ready ? KukuStatusTone.success : .warning).iconColor)
                // Fixed icon column so the text doesn't shift when the symbol changes.
                .frame(width: 18)

            VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                Text(appState.text("快捷键状态", "Shortcut status"))
                    .font(.kuku(.body))
                    .foregroundStyle(KukuColor.textPrimary)
                Text(appState.shortcutStatus.title(appState))
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
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
                .font(.kuku(.subheadline))
                .foregroundStyle(KukuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: KukuSpacing.md)

            if appState.shortcutStatus == .accessibilityRequired {
                Button(appState.text("启用 Fn", "Enable Fn")) {
                    Task { await appState.requestPermission(.accessibility) }
                }
                .buttonStyle(.kukuSecondary)
            } else {
                Button(appState.text("键盘设置", "Keyboard Settings")) {
                    appState.openKeyboardSettings()
                }
                .buttonStyle(.kukuSecondary)
            }
        }
        .kukuRowFrame()
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
            KukuGroup(appState.text("存储", "Storage")) {
                KukuRow(
                    appState.text("自动删除", "Delete history after"),
                    caption: appState.text("星标记录不受此期限影响", "Starred items are never deleted automatically")
                ) {
                    Picker(appState.text("自动删除", "Delete history after"), selection: $appState.historyRetention) {
                        ForEach(HistoryRetention.allCases) { retention in
                            Text(retention.title(appState)).tag(retention)
                        }
                    }
                    .labelsHidden()
                    .frame(width: KukuLayout.pickerWidth)
                }

                KukuDivider()

                KukuToggleRow(
                    title: appState.text("保存录音", "Save recordings"),
                    caption: appState.text(
                        "保留录音，方便回放和重新识别，并随对应的历史记录一起删除",
                        "Keep recordings so you can replay or retry them. They’re deleted with their history items."
                    ),
                    isOn: $appState.storeVoiceAudio
                )
            }

            KukuGroup(appState.text("管理", "Manage")) {
                KukuRow(
                    appState.text("清空全部历史", "Clear all history"),
                    caption: appState.text("删除这台 Mac 上的所有历史记录和录音", "Remove every history item and recording from this Mac")
                ) {
                    Button(appState.text("清空…", "Clear…")) { isConfirmingClear = true }
                        .buttonStyle(.kukuSecondary)
                        .disabled(appState.historyEntries.isEmpty)
                }
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
            Picker(title, selection: $selection) {
                ForEach(Option.allCases) { option in
                    Text(label(option)).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: KukuLayout.pickerWidth)
        }
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
}
