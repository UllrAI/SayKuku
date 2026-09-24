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
                    "SayKuku 通过 Qwen 识别语音、处理指令。填入阿里云百炼的 API Key，选好地域就能开始。",
                    "SayKuku uses Qwen to transcribe your voice and handle commands. Add your Alibaba Cloud Model Studio API Key and pick a region to get started."
                )
            ) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(KukuColor.coral)
            }
            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 14) {
                QwenConnectionForm(apiKeyDraft: $apiKeyDraft)
                    .kukuSurface(radius: KukuLayout.radiusMedium)
                Link(destination: apiKeyHelpURL) {
                    Label(appState.text("如何获取 API Key", "How to get an API Key"), systemImage: "arrow.up.right.square")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(KukuColor.coral)
                .padding(.leading, 4)
                QwenConnectionStatus()
                    .padding(.leading, 4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 640, height: 470)
        .background(KukuColor.canvas)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(appState.text("以后可在“设置 › Qwen 连接”中修改。", "You can change this later in Settings › Qwen Connection."))
                .font(.system(size: 10.5))
                .foregroundStyle(KukuColor.stone)
            Spacer()
            if isConnected {
                Button(appState.text("完成", "Done")) { dismiss() }
                    .buttonStyle(HoverFillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(appState.apiKey.isEmpty ? appState.text("跳过", "Skip") : appState.text("完成", "Done")) {
                    dismiss()
                }
                .buttonStyle(HoverFillButtonStyle())
                .keyboardShortcut(.cancelAction)
                // Applies to the Button inside, so Return saves and tests the key.
                QwenTestButton(apiKeyDraft: apiKeyDraft)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var isConnected: Bool {
        if case .connected = appState.connectionState { return true }
        return false
    }

    private var apiKeyHelpURL: URL {
        URL(string: appState.usesChineseUI
            ? "https://help.aliyun.com/zh/model-studio/get-api-key"
            : "https://www.alibabacloud.com/help/en/model-studio/get-api-key")!
    }
}
