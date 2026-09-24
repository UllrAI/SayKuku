import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: SettingsSection = .general

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: appState.text("设置", "Settings"),
                title: appState.text("按你的习惯使用 SayKuku", "Make SayKuku work your way")
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
        SettingsStack(title: appState.voiceInputTitle, subtitle: appState.text("Fn 只负责忠实输入，不改变你的意思。", "Fn types faithfully without changing your meaning.")) {
            SettingsGroup(title: appState.text("输入方式", "Input gesture")) {
                VStack(spacing: 0) {
                    ForEach(InputMode.allCases) { mode in
                        ChoiceRow(
                            title: mode == .hold ? appState.text("按住 Fn", "Hold Fn") : appState.text("单击 Fn", "Tap Fn"),
                            subtitle: mode == .hold
                                ? appState.text("短暂按住后开始录音，松开后提交", "Starts after a short hold, commits on release")
                                : appState.text("单击开始，再次单击结束", "Tap once to start, again to stop"),
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
                SettingsToggle(title: appState.text("自动检测停顿结束", "Stop after a pause"), subtitle: appState.text("停顿约 1 秒后结束录音", "Stop recording after about one second of silence"), isOn: $appState.autoStop)
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

            SettingsGroup(title: appState.text("帮助识别的词汇", "Recognition vocabulary")) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.text("常用领域与词汇", "Domains & vocabulary"))
                            .font(.system(size: 12.5, weight: .medium))
                        Text(domainSummary)
                            .font(.system(size: 10.5))
                            .foregroundStyle(KukuColor.stone)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 16)
                    Button(appState.text("编辑", "Edit")) {
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
            ? appState.text("尚未选择；可添加 Vibe Coding 等常用词", "None selected; add terms such as Vibe Coding")
            : values.joined(separator: " · ")
    }
}

private struct VoiceAgentSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsStack(title: appState.voiceAgentTitle, subtitle: appState.text("连按两次 Fn，说出要写、修改或查询的内容。", "Press Fn twice to write, edit, or ask by voice.")) {
            SettingsGroup(title: appState.text("交互", "Interaction")) {
                SettingsToggle(title: appState.text("连续对话", "Continue conversation"), subtitle: appState.text("记住同一应用中最近的交流，30 分钟后自动清除", "Remember recent exchanges in the same app for 30 minutes"), isOn: $appState.continuousConversation)
                SettingsDivider()
                SettingsToggle(
                    title: appState.text("自动写回", "Automatic write-back"),
                    subtitle: appState.text("默认开启；关闭后生成文字停留在浮层，可手动复制", "On by default; when off, generated text stays in the overlay for manual copying"),
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
        SettingsStack(title: appState.text("语音 Agent 可使用的内容", "What Voice Agent can use"), subtitle: appState.text("开始说话时，可在浮层查看本次会使用哪些内容。", "See what will be used from the listening overlay.")) {
            SettingsGroup(title: appState.text("允许使用", "Allow access to")) {
                SettingsToggle(title: appState.text("选中文字", "Selected text"), subtitle: appState.text("仅在使用语音 Agent 时读取", "Read only when using Voice Agent"), isOn: $appState.selectedTextAllowed)
                SettingsDivider()
                SettingsToggle(title: appState.text("当前应用", "Current app"), subtitle: appState.text("应用名称及标识符", "App name and identifier"), isOn: $appState.currentAppAllowed)
                SettingsDivider()
                SettingsToggle(title: appState.text("窗口标题", "Window title"), subtitle: appState.text("不会读取无痕浏览窗口", "Private browsing windows are excluded"), isOn: $appState.windowTitleAllowed)
                SettingsDivider()
                SettingsToggle(title: appState.text("剪贴板", "Clipboard"), subtitle: appState.text("仅在使用语音 Agent 时读取", "Read only when using Voice Agent"), isOn: $appState.clipboardAllowed)
                SettingsDivider()
                SettingsToggle(title: appState.text("浏览器页面", "Browser page"), subtitle: appState.text("读取 Safari 或 Chrome 当前页面的网址", "Read the current Safari or Chrome page URL"), isOn: $appState.browserPageAllowed)
            }
            SettingsGroup(title: appState.text("永不访问", "Never access")) {
                HStack(spacing: 10) {
                    PrivacyApp(name: "1Password", symbol: "key.fill")
                    PrivacyApp(name: appState.text("银行应用", "Banking apps"), symbol: "building.columns.fill")
                    PrivacyApp(name: appState.text("无痕浏览", "Private browsing"), symbol: "eye.slash.fill")
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
        SettingsStack(title: appState.text("Qwen 连接", "Qwen connection"), subtitle: appState.text("连接 Qwen，并选择语音输入和语音 Agent 使用的模型。", "Connect Qwen and choose models for Voice Input and Voice Agent.")) {
            SettingsGroup(title: appState.text("连接", "Connection")) {
                QwenConnectionForm(apiKeyDraft: $apiKeyDraft)
            }
            SettingsGroup(title: appState.text("模型", "Models")) {
                ModelPickerRow(title: appState.voiceInputTitle, value: $appState.realtimeModel, presets: QwenModelCatalog.realtimeModels)
                SettingsDivider()
                ModelPickerRow(title: appState.voiceAgentTitle, value: $appState.reasoningModel, presets: QwenModelCatalog.reasoningModels)
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

    var body: some View {
        @Bindable var appState = appState
        let keyState = APIKeyDraftState(draft: apiKeyDraft, saved: appState.apiKey)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(appState.text("地域", "Region")).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Picker("", selection: $appState.qwenRegion) {
                    ForEach(QwenRegion.allCases) { region in
                        Text(region.title(isChineseUI: appState.usesChineseUI)).tag(region)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            SettingsDivider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("API Key").font(.system(size: 12, weight: .medium))
                    Text(keyCaption(keyState))
                        .font(.system(size: 10))
                        .foregroundStyle(keyCaptionColor(keyState))
                }
                Spacer()
                SecureField("sk-...", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit(saveKey)
                Button(appState.text("保存", "Save"), action: saveKey)
                    .buttonStyle(HoverFillButtonStyle())
                    .disabled(!keyState.hasChanges)
            }
            .padding(14)
            SettingsDivider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.text("业务空间 ID", "Workspace ID")).font(.system(size: 12, weight: .medium))
                    Text(appState.text("如 Qwen 提供了业务空间 ID，请填在这里", "Enter your Qwen workspace ID if you have one"))
                        .font(.system(size: 10)).foregroundStyle(KukuColor.stone)
                }
                Spacer()
                TextField("ws-...", text: $appState.qwenWorkspaceID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            .padding(14)
        }
        .onChange(of: appState.apiKey, initial: true) { _, saved in apiKeyDraft = saved }
    }

    private func keyCaption(_ state: APIKeyDraftState) -> String {
        switch state {
        case .empty: appState.text("仅保存在这台 Mac 上", "Stored only on this Mac")
        case .saved: appState.text("已保存在这台 Mac 上", "Saved on this Mac")
        case .modified: appState.text("尚未保存", "Not saved yet")
        case .cleared: appState.text("保存后将移除", "Will be removed when you save")
        }
    }

    private func keyCaptionColor(_ state: APIKeyDraftState) -> Color {
        switch state {
        case .empty: KukuColor.stone
        case .saved: KukuColor.mint
        case .modified, .cleared: KukuColor.amber
        }
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
            Label(
                appState.text(
                    "连接正常 · 语音输入 \(realtime) ms · 语音 Agent \(chat) ms",
                    "Connected · Voice Input \(realtime) ms · Voice Agent \(chat) ms"
                ),
                systemImage: "checkmark.circle.fill"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(KukuColor.mint)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(KukuColor.amber)
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
        Button(isTesting ? appState.text("正在测试…", "Testing…") : appState.text("保存并测试", "Save & test")) {
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
    @Binding var value: String
    let presets: [String]
    @State private var customDraft: String?

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12.5, weight: .medium))
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
                Picker("", selection: selection) {
                    ForEach(QwenModelCatalog.options(presets, including: value), id: \.self) { model in
                        Text(model).tag(Choice.model(model))
                    }
                    Divider()
                    Text(appState.text("自定义…", "Custom…")).tag(Choice.custom)
                }
                .labelsHidden()
                .frame(width: 230)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
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

        SettingsStack(title: appState.text("通用", "General"), subtitle: appState.text("SayKuku 安静地待在需要它的位置。", "SayKuku stays quiet until you need it.")) {
            SettingsGroup(title: appState.text("语言", "Language")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.text("界面语言", "Interface language"))
                            .font(.system(size: 12, weight: .medium))
                        Text(appState.text("默认跟随 macOS，可随时切换", "Follows macOS by default; switch anytime"))
                            .font(.system(size: 10))
                            .foregroundStyle(KukuColor.stone)
                    }
                    Spacer()
                    Picker("", selection: $appState.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title(isChineseUI: appState.usesChineseUI)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 156)
                }
                .padding(14)
            }

            SettingsGroup(title: appState.text("系统权限", "System permissions")) {
                PermissionActionRow(kind: .microphone)
                SettingsDivider()
                PermissionActionRow(kind: .accessibility)
                SettingsDivider()
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.text("权限引导", "Permission guide"))
                            .font(.system(size: 12.5, weight: .medium))
                        Text(appState.text("重新检查状态、开启权限并测试麦克风", "Recheck status, enable access, and test the microphone"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(KukuColor.stone)
                    }
                    Spacer()
                    Button(appState.text("打开引导", "Open guide")) {
                        appState.showPermissionGuide()
                    }
                    .buttonStyle(TintButtonStyle())
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            }

            SettingsGroup(title: appState.text("启动与后台", "Startup & background")) {
                SettingsToggle(
                    title: appState.text("登录时启动", "Launch at login"),
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
                        ? appState.text("仅在菜单栏运行时必须保留", "Required while running only in the menu bar")
                        : appState.text("快速开始输入、打开窗口并查看快捷键状态", "Start input, open the app, and check shortcut status"),
                    isOn: Binding(
                        get: { appState.showInMenuBar },
                        set: { appState.setShowInMenuBar($0) }
                    )
                )
                .disabled(appState.hideDockIconAfterMainWindowCloses)
                SettingsDivider()
                SettingsToggle(
                    title: appState.text("关闭主窗口后仅保留菜单栏图标", "Show only in menu bar after closing"),
                    subtitle: appState.text(
                        "SayKuku 会继续运行；从菜单栏打开窗口时恢复 Dock 图标",
                        "SayKuku keeps running; reopening the window restores its Dock icon"
                    ),
                    isOn: $appState.hideDockIconAfterMainWindowCloses
                )
            }

            SettingsGroup(title: appState.text("全局快捷键", "Global shortcuts")) {
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
                Text(issue?.message(for: action, appState) ?? subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(issue == nil ? KukuColor.stone : KukuColor.amber)
            }
            Spacer(minLength: 12)
            ShortcutRecorderButton(action: action, recorder: recorder)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }

    private var subtitle: String {
        let gesture = action.fnGesture
        if recorder.action == action {
            return appState.text("按下新的组合键 · Esc 取消 · Delete 关闭", "Press new keys · Esc to cancel · Delete to turn off")
        }
        if appState.globalShortcut(for: action) == nil {
            return appState.text("已关闭，仍可使用 \(gesture)", "Off. \(gesture) still works.")
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
                Text(appState.text(
                    "若 Fn 同时切换输入法，请将系统“按 Fn 键时”设为“无操作”；若连按两次 Fn 会打开系统听写，请在键盘设置中更改听写快捷键",
                    "If Fn also switches input sources, set “Press Fn key to” to “Do Nothing”. If pressing Fn twice starts Dictation, change the Dictation shortcut in Keyboard Settings."
                ))
                .font(.system(size: 9.5))
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
            subtitle: appState.text("输入与输出保存在本机，并按期限自动清理。", "Inputs and outputs stay on this Mac and expire automatically.")
        ) {
            SettingsGroup(title: appState.text("保存多久", "Keep history for")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.text("自动清理", "Auto-delete"))
                            .font(.system(size: 12, weight: .medium))
                        Text(appState.text("星标记录不受此期限影响", "Starred items are never deleted automatically"))
                            .font(.system(size: 10))
                            .foregroundStyle(KukuColor.stone)
                    }
                    Spacer()
                    Picker("", selection: $appState.historyRetention) {
                        ForEach(HistoryRetention.allCases) { retention in
                            Text(retention.title(appState)).tag(retention)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                .padding(14)

                SettingsDivider()

                SettingsToggle(
                    title: appState.text("保存录音", "Save recordings"),
                    subtitle: appState.text("录音会和对应的记录一起清理", "Recordings are deleted with their history entries"),
                    isOn: $appState.storeVoiceAudio
                )
            }

            SettingsGroup(title: appState.text("管理", "Manage")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.text("清空全部历史", "Clear all history"))
                            .font(.system(size: 12.5, weight: .medium))
                        Text(appState.text("删除这台 Mac 上的所有输入记录和录音", "Remove every history item and recording from this Mac"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(KukuColor.stone)
                    }
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
                "所有输入记录和录音都会从这台 Mac 上删除，且无法恢复。",
                "All history and recordings will be removed from this Mac. This can't be undone."
            )
        }
        let starredItems = count == 1 ? "1 starred item" : "\(count) starred items"
        return appState.text(
            "“全部删除”会连同 \(count) 条星标记录和所有录音一起删除，且无法恢复。想留下星标内容，请选“保留星标，删除其余”。",
            "Delete All also removes \(starredItems) and every recording. This can't be undone. To keep starred items, choose Delete All but Starred."
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

private struct SettingsToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(KukuColor.stone)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(KukuColor.stone)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).font(.system(size: 12.5, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium)).foregroundStyle(KukuColor.stone)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
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
            Picker("", selection: $selection) {
                ForEach(Option.allCases) { option in
                    Text(label(option)).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 230)
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
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(KukuColor.stone)
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
            .background(Color.black.opacity(0.045), in: Capsule())
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
        case .qwen: appState.text("Qwen 连接", "Qwen connection")
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
