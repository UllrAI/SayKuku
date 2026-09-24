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
                    "SayKuku 通过 Qwen 识别语音、处理指令。填入阿里云百炼的 API Key，选好地域就能开始；再填上业务空间 ID，语音输入会更快。",
                    "SayKuku uses Qwen to transcribe your voice and handle commands. Add your Alibaba Cloud Model Studio API Key and pick a region to get started. Add your Workspace ID too for faster Voice Input."
                )
            ) {
                KukuSheetIcon(symbol: "bolt.horizontal.circle.fill")
            }
            KukuDivider(inset: 0)

            VStack(alignment: .leading, spacing: KukuSpacing.md) {
                // Save & Test in the footer is the only save action during setup.
                QwenConnectionForm(apiKeyDraft: $apiKeyDraft, showsSaveButton: false)
                    .kukuSurface(radius: KukuLayout.radiusMedium)
                QwenConnectionStatus()
                    .padding(.leading, KukuSpacing.xs)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, KukuLayout.sheetPadding)
            .padding(.vertical, KukuSpacing.xl)

            KukuDivider(inset: 0)
            footer
        }
        // Shorter than sheetHeight: the form has only a few rows.
        .frame(width: KukuLayout.sheetWideWidth, height: 470)
        .background(KukuColor.canvas)
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
