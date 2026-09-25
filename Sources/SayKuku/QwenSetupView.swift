import SwiftUI

struct QwenSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var draft = QwenCredentialsDraft()

    var body: some View {
        VStack(spacing: 0) {
            KukuSheetHeader(
                eyebrow: appState.setupProgress?.title,
                title: localized("Connect to Qwen"),
                description: localized(
                    "SayKuku uses Qwen on Alibaba Cloud Model Studio to transcribe your voice and handle commands. Follow the steps below to get an API Key."
                )
            ) {
                KukuSheetIcon(symbol: "bolt.horizontal.circle.fill")
            }
            KukuDivider(inset: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: KukuLayout.sectionSpacing) {
                    KukuGroup(localized("Where to find them")) {
                        steps
                    }
                    VStack(alignment: .leading, spacing: KukuSpacing.md) {
                        KukuGroup(localized("Connection details")) {
                            QwenConnectionForm(draft: $draft)
                        }
                        QwenConnectionStatus(draft: draft)
                            .padding(.leading, KukuSpacing.xs)
                    }
                }
                .padding(.horizontal, KukuLayout.sheetPadding)
                .padding(.vertical, KukuSpacing.xl)
            }

            KukuDivider(inset: 0)
            footer
        }
        // Same size as the other setup steps, so the flow doesn't jump between sheets.
        .frame(width: KukuLayout.sheetWideWidth, height: KukuLayout.sheetHeight)
        .background(KukuColor.canvas)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: KukuSpacing.md) {
            QwenSetupStep(number: 1, text: localized(
                "Sign in to the Alibaba Cloud Model Studio console in the region you pick below."
            )) {
                KukuExternalLink(
                    title: localized("Open Model Studio Console"),
                    destination: appState.qwenRegion.consoleURL
                )
            }
            QwenSetupStep(number: 2, text: localized("On the API Key page, create a key, then paste it below."))
            QwenSetupStep(number: 3, text: localized(
                "Optional: click your avatar in the top-right corner of the console and copy your Workspace ID (it starts with llm-). With it, Voice Input transcribes as you speak."
            ))
        }
        .padding(KukuLayout.rowPadding)
    }

    private var footer: some View {
        KukuSheetFooter(
            note: KukuSheetNote(text: localized("You can change this later in Settings › Qwen Connection."))
        ) {
            if !isConnected {
                QwenConnectionButton(draft: draft, kind: .secondary)
            }
            // The form commits what was typed as the sheet closes, so a key is enough to move on;
            // testing it is recommended, not required.
            Button(draft.hasKey ? appState.setupContinueTitle : appState.setupSkipTitle) { dismiss() }
                .buttonStyle(.kukuPrimary)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Connected, and nothing edited since, so there is nothing left to test.
    private var isConnected: Bool {
        guard case .connected = appState.connectionState else { return false }
        return draft.matches(apiKey: appState.apiKey, workspaceID: appState.qwenWorkspaceID)
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
