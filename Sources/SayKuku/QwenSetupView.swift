import SwiftUI

struct QwenSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var apiKeyDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            KukuSheetHeader(
                eyebrow: appState.setupProgress?.title(appState),
                title: appState.text("连接 Qwen", "Connect to Qwen"),
                description: appState.text(
                    "SayKuku 用阿里云百炼的 Qwen 识别语音、处理指令。按下面的步骤拿到 API Key，就能开始用了。",
                    "SayKuku uses Qwen on Alibaba Cloud Model Studio to transcribe your voice and handle commands. Follow the steps below to get an API Key."
                )
            ) {
                KukuSheetIcon(symbol: "bolt.horizontal.circle.fill")
            }
            KukuDivider(inset: 0)

            VStack(alignment: .leading, spacing: KukuSpacing.lg) {
                steps
                VStack(alignment: .leading, spacing: KukuSpacing.md) {
                    // Save & Test in the footer is the only save action during setup.
                    QwenConnectionForm(apiKeyDraft: $apiKeyDraft, showsSaveButton: false)
                        .kukuSurface(radius: KukuLayout.radiusMedium)
                    QwenConnectionStatus()
                        .padding(.leading, KukuSpacing.xs)
                }
            }
            .padding(.horizontal, KukuLayout.sheetPadding)
            .padding(.vertical, KukuSpacing.xl)

            KukuDivider(inset: 0)
            footer
        }
        // Sized to its content: the steps and the form rows wrap with the language.
        .frame(width: KukuLayout.sheetWideWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(KukuColor.canvas)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: KukuSpacing.sm) {
            QwenSetupStep(number: 1, text: appState.text(
                "登录阿里云百炼控制台，地域与下方所选一致。",
                "Sign in to the Alibaba Cloud Model Studio console in the region you pick below."
            )) {
                KukuExternalLink(
                    title: appState.text("打开百炼控制台", "Open Model Studio Console"),
                    destination: appState.qwenRegion.consoleURL
                )
            }
            QwenSetupStep(number: 2, text: appState.text(
                "在“API Key”页面创建一个 Key，复制后粘贴到下方。",
                "On the API Key page, create a key, then paste it below."
            ))
            QwenSetupStep(number: 3, text: appState.text(
                "可选：点击控制台右上角的头像，复制业务空间 ID（以 llm- 开头）填到下方，语音输入就能边说边识别。",
                "Optional: click your avatar in the top-right corner of the console and copy your Workspace ID (it starts with llm-). With it, Voice Input transcribes as you speak."
            ))
        }
    }

    private var footer: some View {
        KukuSheetFooter(
            note: KukuSheetNote(text: appState.text("以后可在“设置 › Qwen 连接”中修改。", "You can change this later in Settings › Qwen Connection."))
        ) {
            if isConnected {
                Button(appState.text("完成", "Done")) { dismiss() }
                    .buttonStyle(.kukuPrimary)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(appState.apiKey.isEmpty ? appState.text("跳过", "Skip") : appState.text("完成", "Done")) {
                    dismiss()
                }
                .buttonStyle(.kukuSecondary)
                .keyboardShortcut(.cancelAction)
                // Applies to the Button inside, so Return saves and tests the key.
                QwenTestButton(apiKeyDraft: apiKeyDraft)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var isConnected: Bool {
        if case .connected = appState.connectionState { return true }
        return false
    }
}

/// One numbered instruction in the Qwen setup steps.
private struct QwenSetupStep<Accessory: View>: View {
    let number: Int
    let text: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KukuSpacing.sm) {
            Text("\(number)")
                .font(.kuku(.caption, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(KukuColor.textSecondary)
                .frame(width: KukuSpacing.xl, height: KukuSpacing.xl)
                .background(KukuColor.fill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KukuSpacing.xs) {
                Text(text)
                    .font(.kuku(.callout))
                    .foregroundStyle(KukuColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension QwenSetupStep where Accessory == EmptyView {
    init(number: Int, text: String) {
        self.init(number: number, text: text) { EmptyView() }
    }
}
