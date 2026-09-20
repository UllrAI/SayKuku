import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: SettingsSection = .general

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: "Settings",
                title: appState.text("少一些开关，多一点确定", "Fewer switches, more certainty")
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
        SettingsStack(title: "Voice Input", subtitle: appState.text("Fn 只负责忠实输入，不改变你的意思。", "Fn types faithfully without changing your meaning.")) {
            SettingsGroup(title: appState.text("输入方式", "Input gesture")) {
                VStack(spacing: 0) {
                    ForEach(InputMode.allCases) { mode in
                        ChoiceRow(
                            title: mode == .hold ? appState.text("按住 Fn", "Hold Fn") : appState.text("单击 Fn", "Tap Fn"),
                            subtitle: mode == .hold
                                ? appState.text("按下即预缓冲，松开后提交", "Pre-buffer on press, commit on release")
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
                SettingsToggle(title: appState.text("自动检测停顿结束", "Stop after a pause"), subtitle: appState.text("使用 Semantic VAD；默认关闭", "Uses Semantic VAD; off by default"), isOn: $appState.autoStop)
                SettingsDivider()
                SettingsValueRow(title: appState.text("输入位置", "Overlay position"), value: appState.text("光标附近", "Near caret"))
                SettingsDivider()
                SettingsValueRow(title: appState.text("识别语言", "Recognition language"), value: appState.text("自动 · 中英混合", "Auto · Chinese & English"))
                SettingsDivider()
                SettingsValueRow(
                    title: appState.text("数字格式", "Number format"),
                    value: appState.text("优先阿拉伯数字", "Prefer digits")
                )
            }
        }
    }
}

private struct VoiceAgentSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsStack(title: "Voice Agent", subtitle: appState.text("Fn Fn 才会理解、生成或执行动作。", "Fn Fn understands, generates, and acts.")) {
            SettingsGroup(title: appState.text("交互", "Interaction")) {
                SettingsToggle(title: appState.text("连续对话", "Continuous context"), subtitle: appState.text("在当前任务里保留轻量 Session", "Keep a lightweight session for the current task"), isOn: $appState.continuousConversation)
                SettingsDivider()
                SettingsInfoRow(
                    title: appState.text("自动写回", "Automatic write-back"),
                    subtitle: appState.text("有选区时替换，无选区时输入当前光标", "Replace a selection or type at the caret")
                )
            }
        }
    }
}

private struct PrivacySettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsStack(title: "Context & Privacy", subtitle: appState.text("实际发送的 Context 会在确认浮层中按需查看。", "Inspect the exact context from the confirmation overlay.")) {
            SettingsGroup(title: appState.text("允许的上下文", "Allowed context")) {
                SettingsToggle(title: "Selected Text", subtitle: appState.text("仅在 Fn Fn 时读取", "Read only after Fn Fn"), isOn: $appState.selectedTextAllowed)
                SettingsDivider()
                SettingsToggle(title: "Current App", subtitle: appState.text("应用名称与 Bundle ID", "App name and bundle ID"), isOn: $appState.currentAppAllowed)
                SettingsDivider()
                SettingsToggle(title: "Window Title", subtitle: appState.text("自动阻断隐私浏览窗口", "Private browsing is blocked"), isOn: $appState.windowTitleAllowed)
                SettingsDivider()
                SettingsToggle(title: "Clipboard", subtitle: appState.text("默认关闭；仅在 Agent 触发时读取", "Off by default; read only when Agent is triggered"), isOn: $appState.clipboardAllowed)
                SettingsDivider()
                SettingsToggle(title: "Browser Page", subtitle: appState.text("默认关闭；仅支持 Safari 与 Chrome 当前网址", "Off by default; reads the current Safari or Chrome URL"), isOn: $appState.browserPageAllowed)
            }
            SettingsGroup(title: appState.text("永不访问", "Never access")) {
                HStack(spacing: 10) {
                    PrivacyApp(name: "1Password", symbol: "key.fill")
                    PrivacyApp(name: "Banking", symbol: "building.columns.fill")
                    PrivacyApp(name: "Private Browser", symbol: "eye.slash.fill")
                }
                .padding(14)
            }
        }
    }
}

private struct QwenSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsStack(title: "Qwen & API", subtitle: appState.text("为实时听写和意图处理分别选择模型。", "Choose models for live input and intent processing.")) {
            SettingsGroup(title: appState.text("连接", "Connection")) {
                HStack {
                    Text(appState.text("地域", "Region")).font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Picker("", selection: $appState.qwenRegion) {
                        ForEach(QwenRegion.allCases) { Text($0.title).tag($0) }
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
                        Text(appState.text("保存在 macOS Keychain", "Stored in macOS Keychain")).font(.system(size: 10)).foregroundStyle(KukuColor.stone)
                    }
                    Spacer()
                    SecureField("sk-...", text: $appState.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit { try? appState.saveAPIKey(appState.apiKey) }
                    Button(appState.text("保存", "Save")) {
                        do {
                            try appState.saveAPIKey(appState.apiKey)
                            appState.showToast(appState.text("API Key 已安全保存", "API Key saved securely"), symbol: "checkmark.circle.fill")
                        } catch {
                            appState.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                        }
                    }
                    .buttonStyle(HoverFillButtonStyle())
                }
                .padding(14)
                SettingsDivider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Workspace ID").font(.system(size: 12, weight: .medium))
                        Text(appState.text("可选；填写后使用业务空间专属域名", "Optional; enables the workspace-specific endpoint"))
                            .font(.system(size: 10)).foregroundStyle(KukuColor.stone)
                    }
                    Spacer()
                    TextField("ws-...", text: $appState.qwenWorkspaceID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                .padding(14)
            }
            SettingsGroup(title: appState.text("模型", "Models")) {
                SettingsPickerRow(title: "Voice Input", value: $appState.realtimeModel, values: [
                    "qwen3.5-omni-flash-realtime",
                    "qwen3.5-omni-flash-realtime-2026-03-15"
                ])
                SettingsDivider()
                SettingsPickerRow(title: "Voice Agent", value: $appState.reasoningModel, values: [
                    "qwen3.8-omni-flash",
                    "qwen3.5-omni-plus",
                    "qwen3.5-omni-flash"
                ])
            }
            HStack {
                switch appState.connectionState {
                case .connected(let milliseconds):
                    Label(appState.text("连接正常 · \(milliseconds) ms", "Connected · \(milliseconds) ms"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(KukuColor.mint)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(KukuColor.amber)
                        .lineLimit(2)
                default:
                    EmptyView()
                }
                Spacer()
                Button(appState.connectionState == .testing ? appState.text("正在测试…", "Testing…") : appState.text("保存并测试", "Save & test")) {
                    Task { await appState.testQwenConnection() }
                }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
                .disabled(appState.connectionState == .testing || appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        SettingsStack(title: appState.text("通用", "General"), subtitle: appState.text("SayKuku. 安静地待在需要它的位置。", "SayKuku. stays quiet until you need it.")) {
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

            SettingsGroup(title: appState.text("启动", "Startup")) {
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
                    subtitle: appState.text("快速开始输入、打开窗口并查看快捷键状态", "Start input, open the app, and check shortcut status"),
                    isOn: $appState.showInMenuBar
                )
            }

            SettingsGroup(title: appState.text("全局快捷键", "Global shortcuts")) {
                ShortcutStatusRow()
                SettingsDivider()
                SettingsValueRow(title: "Voice Input", value: "Fn · ⇧⌘D")
                SettingsDivider()
                SettingsValueRow(title: "Voice Agent", value: "Fn Fn · ⇧⌘A")
            }
        }
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
                if appState.shortcutStatus == .ready {
                    Text(appState.text(
                        "若 Fn 同时切换输入法，请将系统“按 Fn 键时”设为“无操作”",
                        "If Fn also switches input sources, set “Press Fn key to” to “Do Nothing”"
                    ))
                    .font(.system(size: 9.5))
                    .foregroundStyle(KukuColor.stone)
                }
            }

            Spacer(minLength: 12)

            if appState.shortcutStatus == .accessibilityRequired {
                Button(appState.text("启用 Fn", "Enable Fn")) {
                    Task { await appState.requestPermission(.accessibility) }
                }
                .buttonStyle(TintButtonStyle())
            } else if appState.shortcutStatus == .ready {
                Button(appState.text("键盘设置", "Keyboard Settings")) {
                    appState.openKeyboardSettings()
                }
                .buttonStyle(HoverFillButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }
}

private struct HistorySettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        SettingsStack(
            title: appState.text("历史", "History"),
            subtitle: appState.text("输入与输出保存在本机，并按期限自动清理。", "Inputs and outputs stay on this Mac and expire automatically.")
        ) {
            SettingsGroup(title: appState.text("保留策略", "Retention")) {
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
                    title: appState.text("保存原始语音", "Save original voice"),
                    subtitle: appState.text("与文字历史使用相同的清理和星标规则", "Uses the same retention and star rules as text history"),
                    isOn: $appState.storeVoiceAudio
                )
            }

            Text(appState.text(
                "历史仅保存在本机。关闭“保存原始语音”后，新记录只保留转写和最终输出。",
                "History stays on this Mac. Turn off Save original voice to keep only transcripts and final outputs."
            ))
            .font(.system(size: 10))
            .foregroundStyle(KukuColor.stone)
            .lineSpacing(3)
            .padding(.horizontal, 4)
        }
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

private struct SettingsPickerRow: View {
    let title: String
    @Binding var value: String
    let values: [String]
    var body: some View {
        HStack {
            Text(title).font(.system(size: 12.5, weight: .medium))
            Spacer()
            Picker("", selection: $value) { ForEach(values, id: \.self) { Text($0) } }
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
        case .voiceInput: "Voice Input"
        case .voiceAgent: "Voice Agent"
        case .history: appState.text("历史", "History")
        case .privacy: appState.text("上下文与隐私", "Context & Privacy")
        case .qwen: "Qwen & API"
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
